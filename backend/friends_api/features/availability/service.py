"""Availability (contract section 13): my answers, and a group's heatmap with the best days.

How an answer counts:
- A part of the day (morning, afternoon, evening) is its own entry, else the day's ``all_day``
  entry, else unknown.
- The whole day is the ``all_day`` entry. Without one it comes from the parts: free when all
  three are free, maybe when any is free or maybe, busy when all three are busy, else unknown.
"""

import uuid
from collections import defaultdict
from collections.abc import Iterable, Mapping
from datetime import date, timedelta

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from friends_api.core.errors import FieldError, Unprocessable
from friends_api.features.auth.models import User
from friends_api.features.availability.models import (
    PARTS_OF_DAY,
    Availability,
    AvailabilitySlot,
    AvailabilityStatus,
)
from friends_api.features.availability.schemas import (
    BEST_DAYS,
    MAX_RANGE_DAYS,
    AvailabilityEntry,
    BestDay,
    DayAvailability,
    GroupAvailability,
    MyAvailability,
    MyAvailabilityUpdate,
    SlotCounts,
)
from friends_api.features.groups.models import Membership
from friends_api.features.groups.service import GroupAccess
from friends_api.features.users.schemas import UserPublic

Answers = Mapping[AvailabilitySlot, AvailabilityStatus]
"""One person's entries for one date."""

_FREE, _MAYBE, _BUSY = AvailabilityStatus.FREE, AvailabilityStatus.MAYBE, AvailabilityStatus.BUSY


def slot_status(answers: Answers, slot: AvailabilitySlot) -> AvailabilityStatus | None:
    """A person's status for ``slot`` of a day, or None when unknown."""
    if slot is AvailabilitySlot.ALL_DAY:
        return day_status(answers)
    return answers.get(slot) or answers.get(AvailabilitySlot.ALL_DAY)


def day_status(answers: Answers) -> AvailabilityStatus | None:
    """A person's status for the whole day, or None when unknown."""
    if (whole := answers.get(AvailabilitySlot.ALL_DAY)) is not None:
        return whole
    parts = [answers.get(slot) for slot in PARTS_OF_DAY]
    if all(status is _FREE for status in parts):
        return _FREE
    if any(status in (_FREE, _MAYBE) for status in parts):
        return _MAYBE
    if all(status is _BUSY for status in parts):
        return _BUSY
    return None


def score(free: int, maybe: int) -> float:
    return free + 0.5 * maybe


def _range_error(field: str, message: str, code: str = "validation_error") -> Unprocessable:
    type_ = "value_error" if code == "validation_error" else code
    return Unprocessable(
        message, code=code, errors=[FieldError(field=field, message=message, type=type_)]
    )


def check_range(from_date: date, to_date: date, *, prefix: str) -> None:
    """``to`` after ``from``, and at most 92 days later. ``prefix`` names the fields
    (``query.`` or the body's ``from_date``/``to_date``)."""
    to_field = f"{prefix}to" if prefix == "query." else "to_date"
    if to_date <= from_date:
        raise _range_error(to_field, "The end must be after the start.")
    if (to_date - from_date).days > MAX_RANGE_DAYS:
        raise _range_error(
            to_field, f"The range is at most {MAX_RANGE_DAYS} days.", code="range_too_large"
        )


def _entries(
    db: Session, user_ids: Iterable[uuid.UUID], from_date: date, to_date: date
) -> list[Availability]:
    return list(
        db.scalars(
            select(Availability)
            .where(
                Availability.user_id.in_(list(user_ids)),
                Availability.date >= from_date,
                Availability.date < to_date,
            )
            .order_by(Availability.date, Availability.slot)
        )
    )


_SLOT_ORDER = {slot: index for index, slot in enumerate(AvailabilitySlot)}


def _mine(user: User, from_date: date, to_date: date, rows: list[Availability]) -> MyAvailability:
    rows.sort(key=lambda row: (row.date, _SLOT_ORDER[row.slot]))
    return MyAvailability(
        from_date=from_date,
        to_date=to_date,
        entries=[
            AvailabilityEntry(date=row.date, slot=row.slot, status=row.status) for row in rows
        ],
    )


def my_availability(db: Session, user: User, from_date: date, to_date: date) -> MyAvailability:
    check_range(from_date, to_date, prefix="query.")
    return _mine(user, from_date, to_date, _entries(db, [user.id], from_date, to_date))


def update_my_availability(db: Session, user: User, body: MyAvailabilityUpdate) -> MyAvailability:
    """Replaces my entries in ``[from_date, to_date)`` by the body's."""
    check_range(body.from_date, body.to_date, prefix="")
    errors: list[FieldError] = []
    seen: set[tuple[date, AvailabilitySlot]] = set()
    for index, entry in enumerate(body.entries):
        if not body.from_date <= entry.date < body.to_date:
            errors.append(
                FieldError(
                    field=f"entries.{index}.date",
                    message="Outside the range being saved.",
                    type="value_error",
                )
            )
        elif (entry.date, entry.slot) in seen:
            errors.append(
                FieldError(
                    field=f"entries.{index}",
                    message="Only one answer per date and slot.",
                    type="value_error",
                )
            )
        seen.add((entry.date, entry.slot))
    if errors:
        raise Unprocessable("Some answers can't be saved.", errors=errors)

    db.execute(
        delete(Availability).where(
            Availability.user_id == user.id,
            Availability.date >= body.from_date,
            Availability.date < body.to_date,
        )
    )
    rows = [
        Availability(user_id=user.id, date=entry.date, slot=entry.slot, status=entry.status)
        for entry in body.entries
    ]
    db.add_all(rows)
    db.commit()
    return _mine(user, body.from_date, body.to_date, rows)


def group_availability(
    db: Session, access: GroupAccess, from_date: date, to_date: date
) -> GroupAvailability:
    """The group's current members' answers, counted per day and slot, with the best days."""
    check_range(from_date, to_date, prefix="query.")
    members = list(
        db.scalars(
            select(User)
            .join(Membership, Membership.user_id == User.id)
            .where(Membership.group_id == access.group.id)
            .order_by(User.display_name, User.id)
        )
    )
    answers: dict[tuple[uuid.UUID, date], dict[AvailabilitySlot, AvailabilityStatus]] = defaultdict(
        dict
    )
    for row in _entries(db, (member.id for member in members), from_date, to_date):
        answers[row.user_id, row.date][row.slot] = row.status

    days: list[DayAvailability] = []
    best: list[BestDay] = []
    day = from_date
    while day < to_date:
        slots = []
        for slot in AvailabilitySlot:
            statuses = [(m, slot_status(answers.get((m.id, day), {}), slot)) for m in members]
            counts = SlotCounts(
                slot=slot,
                free=sum(status is _FREE for _, status in statuses),
                maybe=sum(status is _MAYBE for _, status in statuses),
                busy=sum(status is _BUSY for _, status in statuses),
                unknown=sum(status is None for _, status in statuses),
                free_users=[UserPublic.from_user(m) for m, s in statuses if s is _FREE],
                maybe_users=[UserPublic.from_user(m) for m, s in statuses if s is _MAYBE],
            )
            slots.append(counts)
        whole = slots[0]
        day_score = score(whole.free, whole.maybe)
        days.append(DayAvailability(date=day, score=day_score, slots=slots))
        if day_score > 0:
            best.append(
                BestDay(
                    date=day,
                    score=day_score,
                    free=whole.free,
                    maybe=whole.maybe,
                    busy=whole.busy,
                    unknown=whole.unknown,
                )
            )
        day += timedelta(days=1)

    best.sort(key=lambda b: (-b.score, b.busy, b.date))
    return GroupAvailability(
        from_date=from_date,
        to_date=to_date,
        member_count=len(members),
        days=days,
        best_days=best[:BEST_DAYS],
    )
