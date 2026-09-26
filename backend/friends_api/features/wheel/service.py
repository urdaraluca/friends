"""The "What should we do?" wheel (contract sections 3.1, 8.10 and 10).

The server picks the result, so everyone sees the same outcome and nobody can quietly re-roll.
The candidate pool reuses the backlog filters (``activities.filters``), and every slice has the
same weight.
"""

import random
import uuid
from collections.abc import Sequence
from dataclasses import dataclass

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from friends_api.core.db import utcnow
from friends_api.core.errors import Conflict, FieldError, Forbidden, Unprocessable
from friends_api.core.pagination import paginate
from friends_api.features.activities import service as activities_service
from friends_api.features.activities.filters import (
    ActivityFilters,
    filter_activities,
    sort_clauses,
)
from friends_api.features.activities.models import Activity, ActivityStatus
from friends_api.features.auth.models import User
from friends_api.features.categories.service import CategoryIndex
from friends_api.features.group_log.service import log_event
from friends_api.features.groups.models import Group, Membership
from friends_api.features.groups.service import GroupAccess
from friends_api.features.users.lookup import public_user, users_by_id
from friends_api.features.wheel import policies
from friends_api.features.wheel.models import WheelSpin
from friends_api.features.wheel.schemas import (
    MAX_CANDIDATES,
    MIN_CANDIDATES,
    SpinCreate,
    WheelCandidate,
    WheelCandidates,
    WheelFilters,
    WheelSpinPage,
)
from friends_api.features.wheel.schemas import WheelSpin as WheelSpinOut


@dataclass(frozen=True, slots=True)
class SpinAccess:
    """A spin together with the caller's membership in its group."""

    spin: WheelSpin
    membership: Membership


def get_access(db: Session, spin_id: uuid.UUID, user_id: uuid.UUID) -> SpinAccess | None:
    row = db.execute(
        select(WheelSpin, Membership)
        .join(Membership, Membership.group_id == WheelSpin.group_id)
        .where(WheelSpin.id == spin_id, Membership.user_id == user_id)
    ).first()
    return SpinAccess(spin=row[0], membership=row[1]) if row else None


# --- the candidate pool -------------------------------------------------------------------


def activity_filters(filters: WheelFilters) -> ActivityFilters:
    """The backlog filter that selects a wheel's pool (the same semantics as
    ``list_activities``)."""
    return ActivityFilters(
        statuses=filters.status,
        category_id=filters.category_id,
        include_subcategories=filters.include_subcategories,
        owner_id=filters.owner_id,
        interested_by=filters.interested_by,
        cost_max=filters.cost_max,
        include_unpriced=filters.include_unpriced,
        due_before=filters.due_before,
    )


def normalize_filters(filters: WheelFilters) -> WheelFilters:
    """The stored form: statuses deduplicated, in the order of ``ActivityStatus``."""
    wanted = set(filters.status)
    return filters.model_copy(update={"status": [s for s in ActivityStatus if s in wanted]})


def list_candidates(db: Session, access: GroupAccess, filters: WheelFilters) -> WheelCandidates:
    """The pool's size, and its first 50 activities by ``created_at desc, id desc``."""
    pool = filter_activities(access.group, activity_filters(filters))
    total = db.scalar(select(func.count()).select_from(pool.subquery())) or 0
    activities = db.scalars(pool.order_by(*sort_clauses()).limit(MAX_CANDIDATES)).all()
    return WheelCandidates(
        items=activities_service.build_summaries(db, access.membership, activities), total=total
    )


def _load_in_order(db: Session, group: Group, ids: Sequence[uuid.UUID]) -> list[Activity]:
    """The group's activities with these IDs, in that order (unknown IDs are left out)."""
    found = {
        activity.id: activity
        for activity in db.scalars(
            select(Activity).where(Activity.group_id == group.id, Activity.id.in_(ids))
        )
    }
    return [found[activity_id] for activity_id in ids if activity_id in found]


def _pool_slices(
    db: Session, group: Group, filters: WheelFilters, rng: random.Random
) -> list[Activity]:
    """The pool, newest first; over 50, a uniform random sample of 50 (in the same order)."""
    ids = list(
        db.scalars(
            filter_activities(group, activity_filters(filters))
            .with_only_columns(Activity.id)
            .order_by(*sort_clauses())
        )
    )
    if len(ids) > MAX_CANDIDATES:
        chosen = set(rng.sample(ids, MAX_CANDIDATES))
        ids = [activity_id for activity_id in ids if activity_id in chosen]
    return _load_in_order(db, group, ids)


def _hand_picked_slices(
    db: Session, group: Group, activity_ids: Sequence[uuid.UUID]
) -> list[Activity]:
    """The given activities in the given order; duplicates are ignored (the first keeps its
    position). Each must be an activity of the group, else 422 ``invalid_reference`` naming
    ``activity_ids.<index>``."""
    first_index: dict[uuid.UUID, int] = {}
    for index, activity_id in enumerate(activity_ids):
        first_index.setdefault(activity_id, index)
    activities = _load_in_order(db, group, list(first_index))
    found = {activity.id for activity in activities}
    errors = [
        FieldError(
            field=f"activity_ids.{index}",
            message="No such activity in this group.",
            type="invalid_reference",
        )
        for activity_id, index in first_index.items()
        if activity_id not in found
    ]
    if errors:
        raise Unprocessable(
            "Some activities aren't in this group.", code="invalid_reference", errors=errors
        )
    return activities


# --- spinning -----------------------------------------------------------------------------


def create_spin(
    db: Session, access: GroupAccess, body: SpinCreate, *, rng: random.Random
) -> WheelSpin:
    """Builds the slices, picks one with ``rng.randrange`` (equal weights), stores the snapshot
    and logs ``wheel.spun``. ``rng`` is ``secrets.SystemRandom()`` in production. Flushes; the
    caller commits."""
    group, actor = access.group, access.membership
    if not policies.can_spin(actor):
        raise Forbidden("You can't spin this group's wheel.")
    if body.activity_ids is None:
        activities = _pool_slices(db, group, body.filters, rng)
    else:
        # The filters are not applied again: they are stored for display only.
        activities = _hand_picked_slices(db, group, body.activity_ids)
    if len(activities) < MIN_CANDIDATES:
        raise Unprocessable(
            f"The wheel needs at least {MIN_CANDIDATES} activities.",
            code="not_enough_candidates",
        )

    index = CategoryIndex.load(db, group.id)
    candidates = [
        WheelCandidate(
            id=activity.id,
            title=activity.title,
            category_id=activity.category_id,
            color=index.effective_color(activity.category_id),
        )
        for activity in activities
    ]
    result_index = rng.randrange(len(candidates))
    spin = WheelSpin(
        group_id=group.id,
        spun_by_id=actor.user_id,
        filters=normalize_filters(body.filters).model_dump(mode="json"),
        candidates=[candidate.model_dump(mode="json") for candidate in candidates],
        result_index=result_index,
        result_activity_id=candidates[result_index].id,
        created_at=utcnow(),
    )
    db.add(spin)
    db.flush()
    log_event(
        db,
        group_id=group.id,
        actor_id=actor.user_id,
        action="wheel.spun",
        subject_type="spin",
        subject_id=spin.id,
        data={
            "result_activity_id": str(spin.result_activity_id),
            "candidate_count": len(candidates),
        },
    )
    db.flush()
    return spin


def accept(db: Session, spin: WheelSpin, actor: Membership) -> None:
    """Accepts the spin's result; an idea becomes ``planning`` (logged ``via: "wheel"``) and
    other statuses stay. Accepting again changes nothing; accepting a spin whose result has
    been deleted is a 409 ``result_deleted``. Flushes; the caller commits."""
    if not policies.can_accept_spin(actor, spin):
        raise Forbidden("You can't accept this spin.")
    if spin.accepted_at is not None:
        return
    if spin.result_activity_id is None:
        raise Conflict("The picked activity has been deleted.", code="result_deleted")
    activity = db.get_one(Activity, spin.result_activity_id)
    spin.accepted_at = utcnow()
    spin.accepted_by_id = actor.user_id
    log_event(
        db,
        group_id=spin.group_id,
        actor_id=actor.user_id,
        action="wheel.accepted",
        subject_type="spin",
        subject_id=spin.id,
        data={"activity_id": str(activity.id)},
    )
    if activity.status is ActivityStatus.IDEA:
        activities_service.change_status(
            db, activity, ActivityStatus.PLANNING, actor_id=actor.user_id, via="wheel"
        )
    db.flush()


def accept_spin(db: Session, access: SpinAccess) -> None:
    accept(db, access.spin, access.membership)
    db.commit()


# --- reading ------------------------------------------------------------------------------


def _to_spin(spin: WheelSpin, users: dict[uuid.UUID, User]) -> WheelSpinOut:
    candidates = [WheelCandidate.model_validate(raw) for raw in spin.candidates]
    return WheelSpinOut(
        id=spin.id,
        group_id=spin.group_id,
        spun_by=public_user(users, spin.spun_by_id),
        filters=WheelFilters.model_validate(spin.filters),
        candidates=candidates,
        result_index=spin.result_index,
        result=candidates[spin.result_index],
        result_activity_id=spin.result_activity_id,
        accepted_at=spin.accepted_at,
        accepted_by=public_user(users, spin.accepted_by_id),
        created_at=spin.created_at,
    )


def to_spin(db: Session, spin: WheelSpin) -> WheelSpinOut:
    return _to_spin(spin, users_by_id(db, [spin.spun_by_id, spin.accepted_by_id]))


def list_spins(
    db: Session, access: GroupAccess, *, cursor: str | None, limit: int
) -> WheelSpinPage:
    """The group's spins, newest first."""
    query = (
        select(WheelSpin)
        .where(WheelSpin.group_id == access.group.id)
        .order_by(WheelSpin.created_at.desc(), WheelSpin.id.desc())
    )
    spins, next_cursor = paginate(db, query, cursor=cursor, limit=limit)
    users = users_by_id(
        db, (user_id for spin in spins for user_id in (spin.spun_by_id, spin.accepted_by_id))
    )
    return WheelSpinPage(items=[_to_spin(spin, users) for spin in spins], next_cursor=next_cursor)
