import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Any

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from friends_api.core.errors import (
    Conflict,
    FieldError,
    Forbidden,
    NotFound,
    Unprocessable,
)
from friends_api.features.auth.models import User
from friends_api.features.group_log.service import log_event
from friends_api.features.groups import policies
from friends_api.features.groups.models import Group, Membership, Role
from friends_api.features.groups.schemas import (
    AssignableRole,
    GroupCreate,
    GroupSummary,
    GroupUpdate,
    Member,
)
from friends_api.features.groups.schemas import Group as GroupOut
from friends_api.features.users.schemas import BirthdayPublic, UserPublic

MAX_GROUPS_PER_USER = 50
MAX_MEMBERS_PER_GROUP = 100

_ROLE_ORDER = {Role.OWNER: 0, Role.ADMIN: 1, Role.MEMBER: 2}


@dataclass(frozen=True, slots=True)
class GroupAccess:
    """A group together with the caller's membership in it."""

    group: Group
    membership: Membership


def limit_reached(detail: str) -> Unprocessable:
    return Unprocessable(detail, code="limit_reached")


def member_count(db: Session, group_id: uuid.UUID) -> int:
    return db.scalar(select(func.count()).where(Membership.group_id == group_id)) or 0


def ensure_group_has_room(db: Session, group_id: uuid.UUID) -> None:
    if member_count(db, group_id) >= MAX_MEMBERS_PER_GROUP:
        raise limit_reached(f"A group can have at most {MAX_MEMBERS_PER_GROUP} members.")


def ensure_can_join(db: Session, group_id: uuid.UUID, user_id: uuid.UUID) -> None:
    groups = db.scalar(select(func.count()).where(Membership.user_id == user_id)) or 0
    if groups >= MAX_GROUPS_PER_USER:
        raise limit_reached(f"You can be in at most {MAX_GROUPS_PER_USER} groups.")
    ensure_group_has_room(db, group_id)


# --- reading ------------------------------------------------------------------------------


def to_summary(db: Session, group: Group, membership: Membership) -> GroupSummary:
    return GroupSummary(
        id=group.id,
        name=group.name,
        emoji=group.emoji,
        color=group.color,
        member_count=member_count(db, group.id),
        my_role=membership.role,
        created_at=group.created_at,
    )


def to_group(db: Session, group: Group, membership: Membership) -> GroupOut:
    creator = db.get(User, group.created_by_id) if group.created_by_id else None
    return GroupOut(
        **to_summary(db, group, membership).model_dump(),
        description=group.description,
        currency=group.currency,
        timezone=group.timezone,
        members_can_invite=group.members_can_invite,
        created_by=UserPublic.from_user(creator) if creator else None,
        updated_at=group.updated_at,
    )


def list_groups(db: Session, user: User) -> list[GroupSummary]:
    rows = db.execute(
        select(Group, Membership)
        .join(Membership, Membership.group_id == Group.id)
        .where(Membership.user_id == user.id)
        .order_by(func.lower(Group.name), Group.id)
    ).all()
    return [to_summary(db, group, membership) for group, membership in rows]


def get_access(db: Session, group_id: uuid.UUID, user_id: uuid.UUID) -> GroupAccess | None:
    row = db.execute(
        select(Group, Membership)
        .join(Membership, Membership.group_id == Group.id)
        .where(Group.id == group_id, Membership.user_id == user_id)
    ).first()
    return GroupAccess(group=row[0], membership=row[1]) if row else None


def list_members(db: Session, access: GroupAccess) -> list[Member]:
    rows = db.execute(
        select(Membership, User)
        .join(User, User.id == Membership.user_id)
        .where(Membership.group_id == access.group.id)
    ).all()
    me = access.membership.user_id
    members = [_to_member(membership, user, is_me=user.id == me) for membership, user in rows]
    members.sort(key=lambda m: (_ROLE_ORDER[m.role], m.user.display_name.casefold()))
    return members


def _to_member(membership: Membership, user: User, *, is_me: bool) -> Member:
    birthday = None
    if (
        user.birthday_month is not None
        and user.birthday_day is not None
        and (is_me or membership.show_birthday)
    ):
        birthday = BirthdayPublic(month=user.birthday_month, day=user.birthday_day)
    return Member(
        user=UserPublic.from_user(user),
        role=membership.role,
        joined_at=membership.joined_at,
        birthday=birthday,
        show_birthday=membership.show_birthday if is_me else None,
    )


def get_member(db: Session, access: GroupAccess, user_id: uuid.UUID) -> Member:
    membership = db.get(Membership, (access.group.id, user_id))
    user = db.get(User, user_id)
    if membership is None or user is None:
        raise NotFound("No such member.")
    return _to_member(membership, user, is_me=user_id == access.membership.user_id)


# --- writing ------------------------------------------------------------------------------


def create_group(db: Session, user: User, body: GroupCreate) -> GroupAccess:
    groups = db.scalar(select(func.count()).where(Membership.user_id == user.id)) or 0
    if groups >= MAX_GROUPS_PER_USER:
        raise limit_reached(f"You can be in at most {MAX_GROUPS_PER_USER} groups.")
    group = Group(
        name=body.name,
        description=body.description,
        emoji=body.emoji,
        color=body.color,
        currency=body.currency,
        timezone=body.timezone or user.timezone,
        members_can_invite=body.members_can_invite,
        created_by_id=user.id,
    )
    db.add(group)
    db.flush()
    membership = Membership(group_id=group.id, user_id=user.id, role=Role.OWNER)
    db.add(membership)
    log_event(
        db,
        group_id=group.id,
        actor_id=user.id,
        action="group.created",
        subject_type="group",
        subject_id=group.id,
    )
    log_event(
        db,
        group_id=group.id,
        actor_id=user.id,
        action="member.joined",
        subject_type="member",
        subject_id=user.id,
        data={"via": "create", "invite_id": None},
    )
    db.flush()
    return GroupAccess(group=group, membership=membership)


def update_group(db: Session, access: GroupAccess, body: GroupUpdate) -> None:
    if not policies.can_edit_group(access.membership):
        raise Forbidden("Only admins can edit the group.")
    group = access.group
    changed: list[str] = []
    for field, value in body.model_dump().items():
        if getattr(group, field) != value:
            setattr(group, field, value)
            changed.append(field)
    if changed:
        log_event(
            db,
            group_id=group.id,
            actor_id=access.membership.user_id,
            action="group.updated",
            subject_type="group",
            subject_id=group.id,
            data={"fields": changed},
        )
    db.commit()


def delete_group(db: Session, access: GroupAccess) -> None:
    if not policies.can_delete_group(access.membership):
        raise Forbidden("Only the owner can delete the group.")
    _delete_group(db, access.group.id)
    db.commit()


def _delete_group(db: Session, group_id: uuid.UUID) -> None:
    # Everything in the group goes with it (ON DELETE CASCADE).
    db.execute(delete(Group).where(Group.id == group_id))
    db.expunge_all()


def transfer_ownership(db: Session, access: GroupAccess, target_user_id: uuid.UUID) -> None:
    if not policies.can_manage_roles(access.membership):
        raise Forbidden("Only the owner can transfer ownership.")
    if target_user_id == access.membership.user_id:
        raise Unprocessable(
            "You already own this group.",
            errors=[
                FieldError(field="user_id", message="Pick another member.", type="value_error")
            ],
        )
    target = db.get(Membership, (access.group.id, target_user_id))
    if target is None:
        raise invalid_reference("user_id", "Not a member of this group.")
    _transfer(db, access.group.id, access.membership, target, actor_id=access.membership.user_id)
    db.commit()


def _transfer(
    db: Session,
    group_id: uuid.UUID,
    old_owner: Membership,
    new_owner: Membership,
    *,
    actor_id: uuid.UUID | None,
) -> None:
    # Demote first: the partial unique index allows only one owner at a time.
    old_owner.role = Role.ADMIN
    db.flush()
    new_owner.role = Role.OWNER
    log_event(
        db,
        group_id=group_id,
        actor_id=actor_id,
        action="group.ownership_transferred",
        subject_type="member",
        subject_id=new_owner.user_id,
        data={"from": str(old_owner.user_id), "to": str(new_owner.user_id)},
    )
    db.flush()


def invalid_reference(field: str, message: str) -> Unprocessable:
    return Unprocessable(
        message,
        code="invalid_reference",
        errors=[FieldError(field=field, message=message, type="invalid_reference")],
    )


def update_member_role(
    db: Session, access: GroupAccess, user_id: uuid.UUID, role: AssignableRole
) -> None:
    if not policies.can_manage_roles(access.membership):
        raise Forbidden("Only the owner can change roles.")
    target = db.get(Membership, (access.group.id, user_id))
    if target is None:
        raise NotFound("No such member.")
    if target.role is Role.OWNER:
        raise Conflict("Transfer ownership instead.", code="owner_must_transfer")
    new_role = Role(role.value)
    if target.role is not new_role:
        log_event(
            db,
            group_id=access.group.id,
            actor_id=access.membership.user_id,
            action="member.role_changed",
            subject_type="member",
            subject_id=user_id,
            data={"from": target.role.value, "to": new_role.value},
        )
        target.role = new_role
    db.commit()


def remove_member(db: Session, access: GroupAccess, user_id: uuid.UUID) -> None:
    """Removes someone, or leaves the group when ``user_id`` is the caller."""
    actor = access.membership
    if user_id == actor.user_id:
        if actor.is_owner:
            if member_count(db, access.group.id) > 1:
                raise Conflict("Transfer ownership before leaving.", code="owner_must_transfer")
            _delete_group(db, access.group.id)
        else:
            end_membership(
                db, actor, actor_id=actor.user_id, action="member.left", data={"reason": "left"}
            )
        db.commit()
        return

    target = db.get(Membership, (access.group.id, user_id))
    if target is None:
        raise NotFound("No such member.")
    if not policies.can_remove_member(actor, target):
        raise Forbidden("You can't remove this member.")
    end_membership(db, target, actor_id=actor.user_id, action="member.removed", data={})
    db.commit()


def update_my_settings(db: Session, access: GroupAccess, *, show_birthday: bool) -> None:
    membership = access.membership
    if membership.show_birthday != show_birthday:
        membership.show_birthday = show_birthday
        log_event(
            db,
            group_id=access.group.id,
            actor_id=membership.user_id,
            action="member.settings_updated",
            subject_type="member",
            subject_id=membership.user_id,
            data={"show_birthday": show_birthday},
        )
    db.commit()


def end_membership(
    db: Session,
    membership: Membership,
    *,
    actor_id: uuid.UUID | None,
    action: str,
    data: dict[str, Any],
) -> None:
    """Leave / removal / account deletion (contract section 7.5); the caller commits.

    Later features add their clean-up here: the member's interests and votes in the group are
    deleted and the activities they own become unowned. Authored content is kept.
    """
    for cleanup in MEMBERSHIP_END_CLEANUPS:
        cleanup(db, membership.group_id, membership.user_id)
    db.delete(membership)
    log_event(
        db,
        group_id=membership.group_id,
        actor_id=actor_id,
        action=action,
        subject_type="member",
        subject_id=membership.user_id,
        data=data,
    )
    db.flush()


MEMBERSHIP_END_CLEANUPS: list[Any] = []
"""Callables ``(db, group_id, user_id) -> None`` registered by features that store per-member
data (interests, votes, activity ownership)."""


def transfer_or_delete_owned_groups(db: Session, user: User) -> None:
    """Before an account is deleted: hand each owned group to the oldest admin (else the
    oldest member), or delete it if the user is the only member."""
    owned: Sequence[Membership] = db.scalars(
        select(Membership).where(Membership.user_id == user.id, Membership.role == Role.OWNER)
    ).all()
    for membership in owned:
        successor = db.scalars(
            select(Membership)
            .where(Membership.group_id == membership.group_id, Membership.user_id != user.id)
            .order_by(
                (Membership.role == Role.ADMIN).desc(), Membership.joined_at, Membership.user_id
            )
            .limit(1)
        ).first()
        if successor is None:
            db.execute(delete(Group).where(Group.id == membership.group_id))
        else:
            _transfer(db, membership.group_id, membership, successor, actor_id=user.id)
    db.flush()
