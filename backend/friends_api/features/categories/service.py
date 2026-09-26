"""Categories, subcategories and their custom-field definitions (contract sections 6, 8.6)."""

import uuid
from collections import defaultdict
from collections.abc import Callable, Iterable, Sequence
from dataclasses import dataclass
from typing import Any, Self

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from friends_api.core.errors import Conflict, FieldError, Forbidden, Unprocessable
from friends_api.features.auth.models import User
from friends_api.features.categories import policies
from friends_api.features.categories.models import Category
from friends_api.features.categories.schemas import (
    MAX_POSITION,
    CategoryNode,
    CategoryWrite,
    FieldDef,
)
from friends_api.features.categories.schemas import Category as CategoryOut
from friends_api.features.group_log.service import log_event
from friends_api.features.groups.models import Membership
from friends_api.features.groups.service import GroupAccess, invalid_reference, limit_reached
from friends_api.features.users.lookup import public_user, users_by_id

MAX_CATEGORIES_PER_GROUP = 100

CategoryReassignHook = Callable[[Session, uuid.UUID, list[uuid.UUID], uuid.UUID | None], None]

CATEGORY_REASSIGN_HOOKS: list[CategoryReassignHook] = []
"""Called as ``hook(db, group_id, from_category_ids, to_category_id)`` when deleting a category
moves its items: a subcategory's items go to its parent, a top-level category's items (and its
subcategories' items) become uncategorized (``to_category_id`` is ``None``). Each feature with
categorized rows registers one (activities do; events will) and bumps ``version`` on the rows
it changes (contract section 1.7)."""


@dataclass(frozen=True, slots=True)
class CategoryAccess:
    """A category together with the caller's membership in its group."""

    category: Category
    membership: Membership


def get_access(db: Session, category_id: uuid.UUID, user_id: uuid.UUID) -> CategoryAccess | None:
    row = db.execute(
        select(Category, Membership)
        .join(Membership, Membership.group_id == Category.group_id)
        .where(Category.id == category_id, Membership.user_id == user_id)
    ).first()
    return CategoryAccess(category=row[0], membership=row[1]) if row else None


# --- field definitions --------------------------------------------------------------------


def own_field_defs(category: Category) -> list[FieldDef]:
    return [FieldDef.model_validate(raw) for raw in category.field_defs]


class CategoryIndex:
    """All categories of a group, for effective values (color, field definitions) without a
    query per row. Loading it is one query (a group has at most 100 categories)."""

    def __init__(self, categories: Iterable[Category]) -> None:
        self._by_id = {category.id: category for category in categories}
        self._own_defs: dict[uuid.UUID, list[FieldDef]] = {}

    @classmethod
    def load(cls, db: Session, group_id: uuid.UUID) -> Self:
        return cls(db.scalars(select(Category).where(Category.group_id == group_id)))

    def get(self, category_id: uuid.UUID | None) -> Category | None:
        return self._by_id.get(category_id) if category_id is not None else None

    def parent_of(self, category: Category) -> Category | None:
        return self.get(category.parent_id)

    def own_field_defs(self, category: Category) -> list[FieldDef]:
        if category.id not in self._own_defs:
            self._own_defs[category.id] = own_field_defs(category)
        return self._own_defs[category.id]

    def effective_color(self, category_id: uuid.UUID | None) -> str | None:
        category = self.get(category_id)
        if category is None:
            return None
        parent = self.parent_of(category)
        return category.color or (parent.color if parent else None)

    def effective_field_defs(self, category_id: uuid.UUID | None) -> list[FieldDef]:
        """The parent's definitions followed by the category's own; none when uncategorized."""
        category = self.get(category_id)
        if category is None:
            return []
        parent = self.parent_of(category)
        inherited = self.own_field_defs(parent) if parent else []
        return [*inherited, *self.own_field_defs(category)]


# --- reading ------------------------------------------------------------------------------


def _fields(
    category: Category, index: CategoryIndex, actor: Membership, users: dict[uuid.UUID, User]
) -> dict[str, Any]:
    return {
        "id": category.id,
        "group_id": category.group_id,
        "parent_id": category.parent_id,
        "name": category.name,
        "color": category.color,
        "effective_color": index.effective_color(category.id),
        "icon": category.icon,
        "position": category.position,
        "field_defs": index.own_field_defs(category),
        "effective_field_defs": index.effective_field_defs(category.id),
        "created_by": public_user(users, category.created_by_id),
        "can_edit": policies.can_edit_category(actor, category),
        "can_delete": policies.can_delete_category(actor, category),
        "created_at": category.created_at,
        "updated_at": category.updated_at,
    }


def to_category(db: Session, category: Category, actor: Membership) -> CategoryOut:
    index = CategoryIndex.load(db, category.group_id)
    users = users_by_id(db, [category.created_by_id])
    return CategoryOut(**_fields(category, index, actor, users))


def list_categories(db: Session, access: GroupAccess) -> list[CategoryNode]:
    """Top-level categories by (position, name), each with its subcategories in that order."""
    categories: Sequence[Category] = db.scalars(
        select(Category)
        .where(Category.group_id == access.group.id)
        .order_by(Category.position, Category.name, Category.id)
    ).all()
    index = CategoryIndex(categories)
    users = users_by_id(db, (category.created_by_id for category in categories))
    children: defaultdict[uuid.UUID, list[Category]] = defaultdict(list)
    for category in categories:
        if category.parent_id is not None:
            children[category.parent_id].append(category)
    actor = access.membership
    return [
        CategoryNode(
            **_fields(category, index, actor, users),
            subcategories=[
                CategoryOut(**_fields(child, index, actor, users))
                for child in children[category.id]
            ],
        )
        for category in categories
        if category.parent_id is None
    ]


# --- validation ---------------------------------------------------------------------------


def _depth_exceeded(message: str) -> Unprocessable:
    return Unprocessable(
        message,
        code="category_depth_exceeded",
        errors=[FieldError(field="parent_id", message=message, type="category_depth_exceeded")],
    )


def _has_children(db: Session, category_id: uuid.UUID) -> bool:
    return (
        db.scalar(select(Category.id).where(Category.parent_id == category_id).limit(1)) is not None
    )


def _resolve_parent(
    db: Session, group_id: uuid.UUID, parent_id: uuid.UUID | None, *, moving: Category | None
) -> Category | None:
    """The new parent: top-level and in the same group. ``moving`` is the category being
    updated (a category with subcategories can't get a parent)."""
    if parent_id is None:
        return None
    if moving is not None and parent_id == moving.id:
        raise invalid_reference("parent_id", "A category can't be its own parent.")
    parent = db.get(Category, parent_id)
    if parent is None or parent.group_id != group_id:
        raise invalid_reference("parent_id", "No such category in this group.")
    if parent.parent_id is not None:
        raise _depth_exceeded("A subcategory can't have subcategories.")
    if moving is not None and _has_children(db, moving.id):
        raise _depth_exceeded("A category with subcategories can't become a subcategory.")
    return parent


def _check_unique_keys(field_defs: Sequence[FieldDef]) -> None:
    seen: set[str] = set()
    errors: list[FieldError] = []
    for i, field_def in enumerate(field_defs):
        if field_def.key in seen:
            errors.append(
                FieldError(
                    field=f"field_defs.{i}.key",
                    message="This key is already used in this category.",
                    type="value_error",
                )
            )
        seen.add(field_def.key)
    if errors:
        raise Unprocessable("Field keys must be unique.", errors=errors)


def _check_no_key_conflicts(field_defs: Sequence[FieldDef], other_keys: set[str]) -> None:
    """``other_keys``: the keys of the parent, or of every subcategory."""
    errors = [
        FieldError(
            field=f"field_defs.{i}.key",
            message="The parent category or a subcategory already uses this key.",
            type="field_key_conflict",
        )
        for i, field_def in enumerate(field_defs)
        if field_def.key in other_keys
    ]
    if errors:
        raise Unprocessable(
            "A field key is used by both a category and its parent or subcategory.",
            code="field_key_conflict",
            errors=errors,
        )


def _check_no_type_changes(stored: Sequence[FieldDef], field_defs: Sequence[FieldDef]) -> None:
    stored_types = {field_def.key: field_def.type for field_def in stored}
    errors = [
        FieldError(
            field=f"field_defs.{i}.type",
            message="Remove the field and add it back to change its type.",
            type="field_type_change",
        )
        for i, field_def in enumerate(field_defs)
        if stored_types.get(field_def.key, field_def.type) is not field_def.type
    ]
    if errors:
        raise Unprocessable("A field's type can't change.", code="field_type_change", errors=errors)


def _ensure_name_free(
    db: Session,
    group_id: uuid.UUID,
    parent_id: uuid.UUID | None,
    name: str,
    *,
    exclude_id: uuid.UUID | None = None,
) -> None:
    # `name` is COLLATE NOCASE, so the comparison is case-insensitive.
    query = select(Category.id).where(Category.group_id == group_id, Category.name == name)
    if parent_id is None:
        query = query.where(Category.parent_id.is_(None))
    else:
        query = query.where(Category.parent_id == parent_id)
    if exclude_id is not None:
        query = query.where(Category.id != exclude_id)
    if db.scalar(query.limit(1)) is not None:
        raise Conflict("A category with this name already exists here.", code="name_taken")


def _next_position(db: Session, group_id: uuid.UUID, parent_id: uuid.UUID | None) -> int:
    query = select(func.max(Category.position)).where(Category.group_id == group_id)
    if parent_id is None:
        query = query.where(Category.parent_id.is_(None))
    else:
        query = query.where(Category.parent_id == parent_id)
    last = db.scalar(query)
    return 0 if last is None else min(last + 1, MAX_POSITION)


def _dump_field_defs(field_defs: Sequence[FieldDef]) -> list[dict[str, Any]]:
    return [field_def.model_dump(mode="json") for field_def in field_defs]


# --- writing ------------------------------------------------------------------------------


def create_category(db: Session, access: GroupAccess, body: CategoryWrite) -> Category:
    """Any member may create one. Flushes; the caller commits."""
    group_id = access.group.id
    count = db.scalar(select(func.count()).where(Category.group_id == group_id)) or 0
    if count >= MAX_CATEGORIES_PER_GROUP:
        raise limit_reached(f"A group can have at most {MAX_CATEGORIES_PER_GROUP} categories.")
    parent = _resolve_parent(db, group_id, body.parent_id, moving=None)
    _check_unique_keys(body.field_defs)
    if parent is not None:
        _check_no_key_conflicts(body.field_defs, {d.key for d in own_field_defs(parent)})
    _ensure_name_free(db, group_id, body.parent_id, body.name)
    category = Category(
        group_id=group_id,
        parent_id=body.parent_id,
        name=body.name,
        color=body.color,
        icon=body.icon,
        position=(
            body.position
            if body.position is not None
            else _next_position(db, group_id, body.parent_id)
        ),
        field_defs=_dump_field_defs(body.field_defs),
        created_by_id=access.membership.user_id,
    )
    db.add(category)
    db.flush()
    log_event(
        db,
        group_id=group_id,
        actor_id=access.membership.user_id,
        action="category.created",
        subject_type="category",
        subject_id=category.id,
        data={"name": category.name},
    )
    db.flush()
    return category


def update_category(db: Session, access: CategoryAccess, body: CategoryWrite) -> None:
    """Last write wins. ``position: null`` keeps the current position."""
    category, actor = access.category, access.membership
    if not policies.can_edit_category(actor, category):
        raise Forbidden("Only the category's creator or an admin can edit it.")
    parent = _resolve_parent(db, category.group_id, body.parent_id, moving=category)
    _check_unique_keys(body.field_defs)
    _check_no_type_changes(own_field_defs(category), body.field_defs)
    if parent is not None:
        other_keys = {d.key for d in own_field_defs(parent)}
    else:
        children = db.scalars(select(Category).where(Category.parent_id == category.id))
        other_keys = {d.key for child in children for d in own_field_defs(child)}
    _check_no_key_conflicts(body.field_defs, other_keys)
    _ensure_name_free(db, category.group_id, body.parent_id, body.name, exclude_id=category.id)

    new_values: dict[str, Any] = {
        "name": body.name,
        "parent_id": body.parent_id,
        "color": body.color,
        "icon": body.icon,
        "position": body.position if body.position is not None else category.position,
        "field_defs": _dump_field_defs(body.field_defs),
    }
    changed = [field for field, value in new_values.items() if getattr(category, field) != value]
    for field in changed:
        setattr(category, field, new_values[field])
    if changed:
        log_event(
            db,
            group_id=category.group_id,
            actor_id=actor.user_id,
            action="category.updated",
            subject_type="category",
            subject_id=category.id,
            data={"name": category.name},
        )
    db.commit()


def delete_category(db: Session, access: CategoryAccess) -> None:
    """A subcategory's items move to its parent. A top-level category's subcategories are
    deleted too, and the items of all of them become uncategorized. Every deleted category,
    subcategories included, gets its own ``category.deleted`` row."""
    category, actor = access.category, access.membership
    if not policies.can_delete_category(actor, category):
        raise Forbidden("Only the category's creator or an admin can delete it.")
    removed: list[tuple[uuid.UUID, str]] = [(category.id, category.name)]
    if category.parent_id is None:
        removed += db.execute(
            select(Category.id, Category.name)
            .where(Category.parent_id == category.id)
            .order_by(Category.position, Category.name, Category.id)
        ).tuples()
    removed_ids = [category_id for category_id, _ in removed]
    for hook in CATEGORY_REASSIGN_HOOKS:
        hook(db, category.group_id, removed_ids, category.parent_id)
    for category_id, name in removed:
        log_event(
            db,
            group_id=category.group_id,
            actor_id=actor.user_id,
            action="category.deleted",
            subject_type="category",
            subject_id=category_id,
            data={"name": name},
        )
    db.execute(delete(Category).where(Category.id.in_(removed_ids)))
    db.commit()
