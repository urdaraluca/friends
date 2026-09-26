"""The activity backlog (contract sections 3.1, 6.3-6.4, 7.2, 7.5 and 8.7)."""

import uuid
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Literal

from sqlalchemy import delete, func, select, update
from sqlalchemy.orm import Session

from friends_api.core.db import utcnow
from friends_api.core.errors import Conflict, Forbidden
from friends_api.core.pagination import paginate
from friends_api.features.activities import derived_events, derived_polls, policies
from friends_api.features.activities.attributes import (
    card_attributes,
    validate_attributes,
    visible_attributes,
)
from friends_api.features.activities.filters import (
    ActivityFilters,
    filter_activities,
    sort_clauses,
)
from friends_api.features.activities.models import Activity, ActivityInterest, ActivityStatus
from friends_api.features.activities.schemas import Activity as ActivityOut
from friends_api.features.activities.schemas import (
    ActivityCreate,
    ActivityPage,
    ActivitySort,
    ActivitySummary,
    ActivityUpdate,
    ActivityWrite,
    InterestState,
    Link,
    SortOrder,
)
from friends_api.features.auth.models import User
from friends_api.features.categories import service as categories_service
from friends_api.features.categories.service import CategoryIndex
from friends_api.features.events.schemas import OccurrenceRef
from friends_api.features.group_log.service import log_event
from friends_api.features.groups import service as groups_service
from friends_api.features.groups.models import Group, Membership
from friends_api.features.groups.service import GroupAccess, invalid_reference
from friends_api.features.users.lookup import public_user, users_by_id
from friends_api.features.users.schemas import UserPublic

StatusChangeVia = Literal["status", "event", "wheel"]
"""What changed an activity's status (``activity.status_changed`` log data, contract 3.2)."""

ActivityDeleteHook = Callable[[Session, Activity], None]

ACTIVITY_DELETE_HOOKS: list[ActivityDeleteHook] = []
"""Called as ``hook(db, activity)`` just before an activity is deleted, in the same
transaction. Interests and polls go with it (``ON DELETE CASCADE``) and spins keep their
snapshot (``SET NULL``); linked events stay, so the events feature registers a hook that sets
their ``activity_id`` to null and bumps their ``version`` (contract sections 1.7 and 3.1)."""


@dataclass(frozen=True, slots=True)
class ActivityAccess:
    """An activity together with the caller's membership in its group."""

    activity: Activity
    membership: Membership


def get_access(db: Session, activity_id: uuid.UUID, user_id: uuid.UUID) -> ActivityAccess | None:
    row = db.execute(
        select(Activity, Membership)
        .join(Membership, Membership.group_id == Activity.group_id)
        .where(Activity.id == activity_id, Membership.user_id == user_id)
    ).first()
    return ActivityAccess(activity=row[0], membership=row[1]) if row else None


# --- reading ------------------------------------------------------------------------------


def _interest_counts(db: Session, activity_ids: Sequence[uuid.UUID]) -> dict[uuid.UUID, int]:
    rows = db.execute(
        select(ActivityInterest.activity_id, func.count())
        .where(ActivityInterest.activity_id.in_(activity_ids))
        .group_by(ActivityInterest.activity_id)
    ).all()
    return {activity_id: count for activity_id, count in rows}  # noqa: C416 - Row, not tuple


def _my_interests(
    db: Session, activity_ids: Sequence[uuid.UUID], user_id: uuid.UUID
) -> set[uuid.UUID]:
    return set(
        db.scalars(
            select(ActivityInterest.activity_id).where(
                ActivityInterest.activity_id.in_(activity_ids), ActivityInterest.user_id == user_id
            )
        )
    )


def interested_user_ids(db: Session, activity_id: uuid.UUID) -> list[uuid.UUID]:
    """Who is interested, in the order they said so."""
    return list(
        db.scalars(
            select(ActivityInterest.user_id)
            .where(ActivityInterest.activity_id == activity_id)
            .order_by(ActivityInterest.created_at, ActivityInterest.user_id)
        )
    )


def _public_users(users: dict[uuid.UUID, User], ids: Sequence[uuid.UUID]) -> list[UserPublic]:
    return [user for user_id in ids if (user := public_user(users, user_id)) is not None]


def _summary_fields(
    activity: Activity,
    *,
    actor: Membership,
    index: CategoryIndex,
    users: dict[uuid.UUID, User],
    interest_count: int,
    interested: bool,
    polls: derived_polls.PollCounters,
    next_occurrence: OccurrenceRef | None,
) -> dict[str, Any]:
    field_defs = index.effective_field_defs(activity.category_id)
    return {
        "id": activity.id,
        "group_id": activity.group_id,
        "title": activity.title,
        "status": activity.status,
        "category_id": activity.category_id,
        "owner": public_user(users, activity.owner_id),
        "due_date": activity.due_date,
        "estimated_cost": activity.estimated_cost,
        "currency": activity.currency,
        "cost_per_person": activity.cost_per_person,
        "interest_count": interest_count,
        "i_am_interested": interested,
        "poll_count": polls.poll_count,
        "open_poll_count": polls.open_poll_count,
        "my_unvoted_poll_count": polls.my_unvoted_poll_count,
        "card_attributes": card_attributes(
            visible_attributes(activity.attributes, field_defs), field_defs
        ),
        "next_occurrence": next_occurrence,
        "can_edit": policies.can_edit_activity(actor, activity),
        "can_delete": policies.can_delete_activity(actor, activity),
        "created_at": activity.created_at,
        "updated_at": activity.updated_at,
    }


def build_summaries(
    db: Session, actor: Membership, activities: Sequence[Activity], *, now: datetime | None = None
) -> list[ActivitySummary]:
    """Cards for activities of ``actor``'s group, with a fixed number of queries whatever the
    page size (no N+1). The wheel's candidate list reuses this."""
    if not activities:
        return []
    now = now or utcnow()
    ids = [activity.id for activity in activities]
    counts = _interest_counts(db, ids)
    mine = _my_interests(db, ids, actor.user_id)
    users = users_by_id(db, (activity.owner_id for activity in activities))
    index = CategoryIndex.load(db, actor.group_id)
    polls = derived_polls.poll_counters(db, ids, actor.user_id, now=now)
    occurrences = derived_events.next_occurrences(db, activities, now=now)
    return [
        ActivitySummary(
            **_summary_fields(
                activity,
                actor=actor,
                index=index,
                users=users,
                interest_count=counts.get(activity.id, 0),
                interested=activity.id in mine,
                polls=polls.get(activity.id, derived_polls.NO_POLLS),
                next_occurrence=occurrences.get(activity.id),
            )
        )
        for activity in activities
    ]


def to_activity(db: Session, access: ActivityAccess) -> ActivityOut:
    activity, actor = access.activity, access.membership
    now = utcnow()
    index = CategoryIndex.load(db, activity.group_id)
    interested_ids = interested_user_ids(db, activity.id)
    users = users_by_id(db, [activity.owner_id, activity.created_by_id, *interested_ids])
    polls = derived_polls.poll_counters(db, [activity.id], actor.user_id, now=now)
    occurrences = derived_events.next_occurrences(db, [activity], now=now)
    return ActivityOut(
        **_summary_fields(
            activity,
            actor=actor,
            index=index,
            users=users,
            interest_count=len(interested_ids),
            interested=actor.user_id in interested_ids,
            polls=polls.get(activity.id, derived_polls.NO_POLLS),
            next_occurrence=occurrences.get(activity.id),
        ),
        description=activity.description,
        notes=activity.notes,
        location_name=activity.location_name,
        address=activity.address,
        links=[Link.model_validate(link) for link in activity.links],
        attributes=visible_attributes(
            activity.attributes, index.effective_field_defs(activity.category_id)
        ),
        interested_users=_public_users(users, interested_ids),
        created_by=public_user(users, activity.created_by_id),
        status_changed_at=activity.status_changed_at,
        completed_at=activity.completed_at,
        version=activity.version,
        events=derived_events.linked_events(db, activity),
    )


def list_activities(
    db: Session,
    access: GroupAccess,
    filters: ActivityFilters,
    *,
    sort: ActivitySort,
    order: SortOrder,
    cursor: str | None,
    limit: int,
) -> ActivityPage:
    query = filter_activities(access.group, filters).order_by(*sort_clauses(sort, order))
    activities, next_cursor = paginate(db, query, cursor=cursor, limit=limit)
    return ActivityPage(
        items=build_summaries(db, access.membership, activities), next_cursor=next_cursor
    )


# --- writing ------------------------------------------------------------------------------


def _check_category(index: CategoryIndex, category_id: uuid.UUID | None) -> None:
    if category_id is not None and index.get(category_id) is None:
        raise invalid_reference("category_id", "No such category in this group.")


def _check_member(db: Session, group_id: uuid.UUID, user_id: uuid.UUID, field: str) -> None:
    if db.get(Membership, (group_id, user_id)) is None:
        raise invalid_reference(field, "Not a member of this group.")


def _written_values(
    body: ActivityWrite, group: Group, attributes: dict[str, Any]
) -> dict[str, Any]:
    """The columns an ``ActivityWrite`` sets (everything but the owner)."""
    has_cost = body.estimated_cost is not None
    return {
        "title": body.title,
        "description": body.description,
        "notes": body.notes,
        "category_id": body.category_id,
        "due_date": body.due_date,
        "estimated_cost": body.estimated_cost,
        "currency": (body.currency or group.currency) if has_cost else None,
        "cost_per_person": body.cost_per_person,
        "location_name": body.location_name,
        "address": body.address,
        "links": [link.model_dump(mode="json") for link in body.links],
        "attributes": attributes,
    }


def create_activity(db: Session, access: GroupAccess, body: ActivityCreate) -> Activity:
    """The creator is marked interested; ``owner_id: null`` means the creator. Flushes; the
    caller commits."""
    group, actor = access.group, access.membership
    index = CategoryIndex.load(db, group.id)
    _check_category(index, body.category_id)
    if body.owner_id is not None:
        _check_member(db, group.id, body.owner_id, "owner_id")
    attributes = validate_attributes(body.attributes, index.effective_field_defs(body.category_id))
    now = utcnow()
    activity = Activity(
        group_id=group.id,
        owner_id=body.owner_id or actor.user_id,
        created_by_id=actor.user_id,
        status=body.status,
        status_changed_at=now,
        completed_at=now if body.status is ActivityStatus.DONE else None,
        created_at=now,
        updated_at=now,
        **_written_values(body, group, attributes),
    )
    db.add(activity)
    db.flush()
    db.add(ActivityInterest(activity_id=activity.id, user_id=actor.user_id, created_at=now))
    log_event(
        db,
        group_id=group.id,
        actor_id=actor.user_id,
        action="activity.created",
        subject_type="activity",
        subject_id=activity.id,
        data={
            "title": activity.title,
            "category_id": str(activity.category_id) if activity.category_id else None,
            "status": activity.status.value,
        },
    )
    db.flush()
    return activity


def update_activity(db: Session, access: ActivityAccess, body: ActivityUpdate) -> None:
    """Full-object PUT with optimistic locking: a stale ``version`` changes nothing."""
    activity, actor = access.activity, access.membership
    if body.version != activity.version:
        raise Conflict("Someone else changed this activity; reload it.", code="version_conflict")
    group = db.get(Group, activity.group_id)
    assert group is not None  # noqa: S101 - activities cascade with their group
    if body.owner_id is not None and body.owner_id != activity.owner_id:
        _check_member(db, group.id, body.owner_id, "owner_id")
    if not policies.can_change_owner(actor, activity, body.owner_id):
        raise Forbidden("You can't change who owns this activity.")
    index = CategoryIndex.load(db, group.id)
    _check_category(index, body.category_id)

    values = dict(body.attributes)
    if body.category_id != activity.category_id:
        # Keys only the old category had are dropped silently (the client warned first).
        old_keys = {d.key for d in index.effective_field_defs(activity.category_id)}
        new_keys = {d.key for d in index.effective_field_defs(body.category_id)}
        values = {k: v for k, v in values.items() if k not in old_keys or k in new_keys}
    attributes = validate_attributes(values, index.effective_field_defs(body.category_id))

    new_values = {**_written_values(body, group, attributes), "owner_id": body.owner_id}
    changed = [field for field, value in new_values.items() if getattr(activity, field) != value]
    for field in changed:
        setattr(activity, field, new_values[field])
    activity.version += 1
    if changed:
        log_event(
            db,
            group_id=group.id,
            actor_id=actor.user_id,
            action="activity.updated",
            subject_type="activity",
            subject_id=activity.id,
            data={"fields": changed},
        )
    db.commit()


def delete_activity(db: Session, access: ActivityAccess) -> None:
    activity, actor = access.activity, access.membership
    if not policies.can_delete_activity(actor, activity):
        raise Forbidden("Only the creator, the owner or an admin can delete this activity.")
    for hook in ACTIVITY_DELETE_HOOKS:
        hook(db, activity)
    log_event(
        db,
        group_id=activity.group_id,
        actor_id=actor.user_id,
        action="activity.deleted",
        subject_type="activity",
        subject_id=activity.id,
        data={"title": activity.title},
    )
    db.delete(activity)  # interests and polls cascade
    db.commit()


def change_status(
    db: Session,
    activity: Activity,
    status: ActivityStatus,
    *,
    actor_id: uuid.UUID | None,
    via: StatusChangeVia,
) -> bool:
    """The one way to change an activity's status, with its side effects: ``status_changed_at``,
    ``completed_at`` (set on entering ``done``, cleared on leaving it) and the
    ``activity.status_changed`` log row. The status endpoint (``via="status"``), event
    scheduling (``"event"``) and accepting a wheel spin (``"wheel"``) all use it.

    Any transition is allowed; the same status is a no-op (returns False). Doesn't touch
    ``version``. Flushes; the caller commits."""
    old = activity.status
    if status == old:
        return False
    now = utcnow()
    activity.status = status
    activity.status_changed_at = now
    if status is ActivityStatus.DONE:
        activity.completed_at = now
    elif old is ActivityStatus.DONE:
        activity.completed_at = None
    log_event(
        db,
        group_id=activity.group_id,
        actor_id=actor_id,
        action="activity.status_changed",
        subject_type="activity",
        subject_id=activity.id,
        data={"from": old.value, "to": status.value, "via": via},
    )
    db.flush()
    return True


def set_activity_status(db: Session, access: ActivityAccess, status: ActivityStatus) -> None:
    change_status(db, access.activity, status, actor_id=access.membership.user_id, via="status")
    db.commit()


# --- interests ----------------------------------------------------------------------------


def mark_interested(db: Session, activity: Activity, user_id: uuid.UUID) -> bool:
    """Idempotent; returns whether anything changed. Flushes; the caller commits."""
    if db.get(ActivityInterest, (activity.id, user_id)) is not None:
        return False
    db.add(ActivityInterest(activity_id=activity.id, user_id=user_id))
    log_event(
        db,
        group_id=activity.group_id,
        actor_id=user_id,
        action="activity.interest_added",
        subject_type="activity",
        subject_id=activity.id,
    )
    db.flush()
    return True


def unmark_interested(db: Session, activity: Activity, user_id: uuid.UUID) -> bool:
    """Idempotent; returns whether anything changed. Flushes; the caller commits."""
    interest = db.get(ActivityInterest, (activity.id, user_id))
    if interest is None:
        return False
    db.delete(interest)
    log_event(
        db,
        group_id=activity.group_id,
        actor_id=user_id,
        action="activity.interest_removed",
        subject_type="activity",
        subject_id=activity.id,
    )
    db.flush()
    return True


def add_interest(db: Session, access: ActivityAccess) -> None:
    mark_interested(db, access.activity, access.membership.user_id)
    db.commit()


def remove_interest(db: Session, access: ActivityAccess) -> None:
    unmark_interested(db, access.activity, access.membership.user_id)
    db.commit()


def interest_state(db: Session, access: ActivityAccess) -> InterestState:
    ids = interested_user_ids(db, access.activity.id)
    users = users_by_id(db, ids)
    return InterestState(
        activity_id=access.activity.id,
        interested=access.membership.user_id in ids,
        interest_count=len(ids),
        interested_users=_public_users(users, ids),
    )


# --- reactions to other features ----------------------------------------------------------


def _on_membership_end(db: Session, group_id: uuid.UUID, user_id: uuid.UUID) -> None:
    """Contract section 7.5: the leaver's interests in the group go, and the activities they
    own become unowned (a change to a written field, so ``version + 1``)."""
    db.execute(
        delete(ActivityInterest).where(
            ActivityInterest.user_id == user_id,
            ActivityInterest.activity_id.in_(
                select(Activity.id).where(Activity.group_id == group_id)
            ),
        )
    )
    db.execute(
        update(Activity)
        .where(Activity.group_id == group_id, Activity.owner_id == user_id)
        .values(owner_id=None, version=Activity.version + 1, updated_at=utcnow())
    )


def _on_category_reassign(
    db: Session, group_id: uuid.UUID, from_ids: list[uuid.UUID], to_id: uuid.UUID | None
) -> None:
    """A deleted category's activities move to its parent or become uncategorized
    (``version + 1``). Their attributes are left as stored: values that don't match the new
    definitions are hidden on read and dropped by the next PUT."""
    db.execute(
        update(Activity)
        .where(Activity.group_id == group_id, Activity.category_id.in_(from_ids))
        .values(category_id=to_id, version=Activity.version + 1, updated_at=utcnow())
    )


groups_service.MEMBERSHIP_END_CLEANUPS.append(_on_membership_end)
categories_service.CATEGORY_REASSIGN_HOOKS.append(_on_category_reassign)
