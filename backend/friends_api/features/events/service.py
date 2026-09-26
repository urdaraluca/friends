"""Calendar events: series, cancelled occurrences and scheduling (contract sections 5.6, 5.8,
7.2 and 8.8). The calendar queries live in ``calendar``."""

import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import Any
from zoneinfo import ZoneInfo

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from friends_api.core.db import utcnow
from friends_api.core.errors import Conflict, FieldError, Forbidden, NotFound, Unprocessable
from friends_api.features.activities import service as activities_service
from friends_api.features.activities.models import Activity, ActivityStatus
from friends_api.features.categories import service as categories_service
from friends_api.features.categories.models import Category
from friends_api.features.categories.service import CategoryIndex
from friends_api.features.events import policies, recurrence
from friends_api.features.events.lookup import activity_owners, cancelled_keys
from friends_api.features.events.models import Event, EventException, EventKind
from friends_api.features.events.schemas import Event as EventOut
from friends_api.features.events.schemas import EventUpdate, EventWrite
from friends_api.features.group_log.service import log_event
from friends_api.features.groups.models import Group, Membership
from friends_api.features.groups.service import GroupAccess, invalid_reference
from friends_api.features.users.lookup import public_user, users_by_id

BIRTHDAY_RRULE = "FREQ=YEARLY"
SCHEDULABLE = (ActivityStatus.IDEA, ActivityStatus.PLANNING)
"""Linking an event to an activity in one of these makes it ``scheduled``."""
TIMING_FIELDS = ("starts_at", "start_date", "all_day", "timezone", "rrule")
"""A PUT that changes one of these deletes every exception of the event: the keys refer to
the old occurrences. Changing only the end (the duration) keeps them."""


@dataclass(frozen=True, slots=True)
class EventAccess:
    """An event together with the caller's membership in its group."""

    event: Event
    membership: Membership


def get_access(db: Session, event_id: uuid.UUID, user_id: uuid.UUID) -> EventAccess | None:
    row = db.execute(
        select(Event, Membership)
        .join(Membership, Membership.group_id == Event.group_id)
        .where(Event.id == event_id, Membership.user_id == user_id)
    ).first()
    return EventAccess(event=row[0], membership=row[1]) if row else None


# --- reading ------------------------------------------------------------------------------


def _activity_owner(db: Session, event: Event) -> uuid.UUID | None:
    if event.activity_id is None:
        return None
    return activity_owners(db, [event.activity_id]).get(event.activity_id)


def to_event(db: Session, access: EventAccess) -> EventOut:
    event, actor = access.event, access.membership
    owner_id = _activity_owner(db, event)
    users = users_by_id(db, [event.created_by_id])
    index = CategoryIndex.load(db, event.group_id)
    return EventOut(
        id=event.id,
        group_id=event.group_id,
        kind=event.kind,
        title=event.title,
        description=event.description,
        all_day=event.all_day,
        starts_at=event.starts_at,
        ends_at=event.ends_at,
        start_date=event.start_date,
        end_date=event.end_date,
        timezone=event.timezone,
        rrule=event.rrule,
        category_id=event.category_id,
        color=index.effective_color(event.category_id),
        activity_id=event.activity_id,
        location_name=event.location_name,
        address=event.address,
        cancelled_occurrence_keys=sorted(cancelled_keys(db, [event.id]).get(event.id, ())),
        version=event.version,
        created_by=public_user(users, event.created_by_id),
        can_edit=policies.can_edit_event(actor, event, owner_id),
        can_delete=policies.can_delete_event(actor, event, owner_id),
        created_at=event.created_at,
        updated_at=event.updated_at,
    )


# --- write rules (section 5.8) -------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class _Validated:
    values: dict[str, Any]
    """The columns an ``EventWrite`` sets, window included."""
    activity: Activity | None


def _normalized_rrule(raw: str) -> str:
    text = raw.strip()
    if text[:6].upper() == "RRULE:":
        text = text[6:]
    return text.upper()


def _in_supported_range(day: date) -> bool:
    return recurrence.MIN_DATE <= day <= recurrence.MAX_DATE


class _Errors:
    def __init__(self) -> None:
        self.items: list[FieldError] = []

    def add(self, field: str, message: str, type_: str = "value_error") -> None:
        self.items.append(FieldError(field=field, message=message, type=type_))

    def missing(self, field: str) -> None:
        self.add(field, "Field required", "missing")


def _timing(body: EventWrite, errors: _Errors) -> dict[str, Any]:
    """``all_day`` and its dates or instants, checked by timing (section 5.8)."""
    birthday = body.kind is EventKind.BIRTHDAY
    all_day = body.all_day
    if birthday and not all_day:
        errors.add("all_day", "A birthday is an all-day event.")
        all_day = True
    timing: dict[str, Any] = {
        "all_day": all_day,
        "starts_at": None,
        "ends_at": None,
        "start_date": None,
        "end_date": None,
    }
    if all_day:
        for field in ("starts_at", "ends_at"):
            if getattr(body, field) is not None:
                errors.add(field, "An all-day event has dates only; leave the times empty.")
        if body.start_date is None:
            errors.missing("start_date")
            return timing
        start_date, end_date = body.start_date, body.end_date or body.start_date
        if birthday and end_date != start_date:
            errors.add("end_date", "A birthday is one day: leave end_date empty.")
        elif end_date < start_date:
            errors.add("end_date", "The end date is before the start date.")
        elif (end_date - start_date).days + 1 > recurrence.MAX_DURATION.days:
            errors.add("end_date", "An event lasts at most 30 days.")
        if not _in_supported_range(start_date):
            errors.add("start_date", "Use a date between the years 1000 and 8999.")
        elif not _in_supported_range(end_date):
            errors.add("end_date", "Use a date between the years 1000 and 8999.")
        timing.update(start_date=start_date, end_date=end_date)
        return timing
    for field in ("start_date", "end_date"):
        if getattr(body, field) is not None:
            errors.add(field, "A timed event has start and end times only; leave the dates empty.")
    if body.starts_at is None:
        errors.missing("starts_at")
    if body.ends_at is None:
        errors.missing("ends_at")
    if body.starts_at is None or body.ends_at is None:
        return timing
    starts_at, ends_at = body.starts_at.astimezone(UTC), body.ends_at.astimezone(UTC)
    if ends_at <= starts_at:
        errors.add("ends_at", "The end must be after the start.")
    elif ends_at - starts_at > recurrence.MAX_DURATION:
        errors.add("ends_at", "An event lasts at most 30 days.")
    for field, instant in (("starts_at", starts_at), ("ends_at", ends_at)):
        if not _in_supported_range(instant.date()):
            errors.add(field, "Use a date between the years 1000 and 8999.")
    timing.update(starts_at=starts_at, ends_at=ends_at)
    return timing


def _check_rrule_presence(body: EventWrite, errors: _Errors) -> None:
    if body.kind is EventKind.ONE_TIME and body.rrule is not None:
        errors.add("rrule", "A one-time event doesn't repeat; leave rrule empty.")
    elif body.kind is EventKind.RECURRING and body.rrule is None:
        errors.missing("rrule")
    elif (
        body.kind is EventKind.BIRTHDAY
        and body.rrule is not None
        and _normalized_rrule(body.rrule) != BIRTHDAY_RRULE
    ):
        errors.add("rrule", "A birthday repeats every year: leave rrule empty or send FREQ=YEARLY.")


def _canonical_rrule(body: EventWrite, timing: dict[str, Any], tz: str) -> str | None:
    if body.kind is EventKind.ONE_TIME:
        return None
    if body.kind is EventKind.BIRTHDAY:
        return BIRTHDAY_RRULE  # not run through section 5.2: 29 February is fine
    assert body.rrule is not None  # noqa: S101 - checked by _check_rrule_presence
    starts_at: datetime | None = timing["starts_at"]
    start_local = (
        timing["start_date"] if starts_at is None else starts_at.astimezone(ZoneInfo(tz)).date()
    )
    try:
        return recurrence.canonicalize_rrule(body.rrule, start_local, timing["all_day"], starts_at)
    except recurrence.InvalidRRule as exc:
        raise Unprocessable(
            "The repeat rule isn't supported.",
            code="invalid_rrule",
            errors=[FieldError(field="rrule", message=exc.message, type=exc.reason)],
        ) from exc


def _referenced_activity(db: Session, group: Group, body: EventWrite) -> Activity | None:
    if body.category_id is not None:
        category = db.get(Category, body.category_id)
        if category is None or category.group_id != group.id:
            raise invalid_reference("category_id", "No such category in this group.")
    if body.activity_id is None:
        return None
    activity = db.get(Activity, body.activity_id)
    if activity is None or activity.group_id != group.id:
        raise invalid_reference("activity_id", "No such activity in this group.")
    return activity


def _validate(db: Session, group: Group, body: EventWrite) -> _Validated:
    """Applies section 5.8: shape errors first (one 422 ``validation_error`` listing all of
    them), then the rule (``invalid_rrule``), then the references (``invalid_reference``)."""
    errors = _Errors()
    timing = _timing(body, errors)
    _check_rrule_presence(body, errors)
    if errors.items:
        raise Unprocessable("Invalid event.", errors=errors.items)
    tz = body.timezone or group.timezone
    rrule = _canonical_rrule(body, timing, tz)
    activity = _referenced_activity(db, group, body)
    window_start, window_end = recurrence.search_window(
        recurrence.Series(kind=body.kind.value, timezone=tz, rrule=rrule, **timing)
    )
    values = {
        "kind": body.kind,
        "title": body.title,
        "description": body.description,
        **timing,
        "timezone": tz,
        "rrule": rrule,
        "category_id": body.category_id,
        "activity_id": body.activity_id,
        "location_name": body.location_name,
        "address": body.address,
        "window_start": window_start,
        "window_end": window_end,
    }
    return _Validated(values=values, activity=activity)


def _schedule(db: Session, activity: Activity | None, actor_id: uuid.UUID) -> None:
    """Section 5.8: linking an activity in ``idea`` or ``planning`` makes it ``scheduled``.
    Unlinking or deleting an event never changes the status back."""
    if activity is not None and activity.status in SCHEDULABLE:
        activities_service.change_status(
            db, activity, ActivityStatus.SCHEDULED, actor_id=actor_id, via="event"
        )


def _log(db: Session, event: Event, action: str, actor_id: uuid.UUID, **data: Any) -> None:
    log_event(
        db,
        group_id=event.group_id,
        actor_id=actor_id,
        action=action,
        subject_type="event",
        subject_id=event.id,
        data=data or {"title": event.title, "kind": event.kind.value},
    )


# --- writing ------------------------------------------------------------------------------


def create_event(db: Session, access: GroupAccess, body: EventWrite) -> Event:
    """Any member. Flushes; the caller commits."""
    group, actor = access.group, access.membership
    validated = _validate(db, group, body)
    event = Event(group_id=group.id, created_by_id=actor.user_id, **validated.values)
    db.add(event)
    db.flush()
    _log(db, event, "event.created", actor.user_id)
    _schedule(db, validated.activity, actor.user_id)
    db.flush()
    return event


def _ensure_can_edit(db: Session, access: EventAccess) -> None:
    if not policies.can_edit_event(
        access.membership, access.event, _activity_owner(db, access.event)
    ):
        raise Forbidden(
            "Only the event's creator, the owner of its activity or an admin can change it."
        )


def update_event(db: Session, access: EventAccess, body: EventUpdate) -> None:
    """Full-object PUT of the whole series, with optimistic locking."""
    event, actor = access.event, access.membership
    _ensure_can_edit(db, access)
    if body.version != event.version:
        raise Conflict("Someone else changed this event; reload it.", code="version_conflict")
    group = db.get(Group, event.group_id)
    assert group is not None  # noqa: S101 - events cascade with their group
    validated = _validate(db, group, body)
    new = validated.values
    resets_exceptions = any(getattr(event, field) != new[field] for field in TIMING_FIELDS)
    links_another = new["activity_id"] is not None and new["activity_id"] != event.activity_id
    changed = [field for field, value in new.items() if getattr(event, field) != value]
    for field in changed:
        setattr(event, field, new[field])
    event.version += 1
    if resets_exceptions:
        for exception in db.scalars(
            select(EventException).where(EventException.event_id == event.id)
        ):
            db.delete(exception)
    if changed:
        _log(db, event, "event.updated", actor.user_id)
    if links_another:
        _schedule(db, validated.activity, actor.user_id)
    db.commit()


def delete_event(db: Session, access: EventAccess) -> None:
    """The whole series; its exceptions cascade. A linked activity keeps its status."""
    event, actor = access.event, access.membership
    if not policies.can_delete_event(actor, event, _activity_owner(db, event)):
        raise Forbidden(
            "Only the event's creator, the owner of its activity or an admin can delete it."
        )
    _log(db, event, "event.deleted", actor.user_id)
    db.delete(event)
    db.commit()


def _check_key(key: str) -> None:
    try:
        recurrence.parse_occurrence_key(key)
    except ValueError as exc:
        raise Unprocessable(
            "Malformed occurrence key.",
            errors=[
                FieldError(
                    field="path.occurrence_key",
                    message="Expected YYYYMMDD or YYYYMMDDTHHMMSSZ.",
                    type="value_error",
                )
            ],
        ) from exc


def _exception(db: Session, event: Event, key: str) -> EventException | None:
    return db.scalar(
        select(EventException).where(
            EventException.event_id == event.id, EventException.occurrence_key == key
        )
    )


def cancel_occurrence(db: Session, access: EventAccess, key: str) -> None:
    """Idempotent. The key must be a real occurrence of the series (else 404); a one-time
    event has none to cancel (delete the event instead)."""
    event, actor = access.event, access.membership
    _ensure_can_edit(db, access)
    _check_key(key)
    if event.kind is EventKind.ONE_TIME:
        raise Unprocessable(
            "A one-time event has a single occurrence; delete the event instead.",
            errors=[
                FieldError(
                    field="path.occurrence_key",
                    message="A one-time event's occurrence can't be cancelled.",
                    type="value_error",
                )
            ],
        )
    if _exception(db, event, key) is not None:
        return
    if not recurrence.is_occurrence(event.series(), key):
        raise NotFound("No such occurrence.")
    db.add(EventException(event_id=event.id, occurrence_key=key, created_by_id=actor.user_id))
    _log(db, event, "event.occurrence_cancelled", actor.user_id, occurrence_key=key)
    db.commit()


def restore_occurrence(db: Session, access: EventAccess, key: str) -> None:
    """Idempotent: restoring an occurrence that isn't cancelled changes nothing."""
    event, actor = access.event, access.membership
    _ensure_can_edit(db, access)
    _check_key(key)
    exception = _exception(db, event, key)
    if exception is None:
        return
    db.delete(exception)
    _log(db, event, "event.occurrence_restored", actor.user_id, occurrence_key=key)
    db.commit()


# --- reactions to other features ----------------------------------------------------------


def _on_activity_delete(db: Session, activity: Activity) -> None:
    """Linked events stay; they lose the link (a written field, so ``version + 1``)."""
    db.execute(
        update(Event)
        .where(Event.activity_id == activity.id)
        .values(activity_id=None, version=Event.version + 1, updated_at=utcnow())
    )


def _on_category_reassign(
    db: Session, group_id: uuid.UUID, from_ids: list[uuid.UUID], to_id: uuid.UUID | None
) -> None:
    """A deleted category's events move to its parent or become uncategorized
    (``version + 1``)."""
    db.execute(
        update(Event)
        .where(Event.group_id == group_id, Event.category_id.in_(from_ids))
        .values(category_id=to_id, version=Event.version + 1, updated_at=utcnow())
    )


activities_service.ACTIVITY_DELETE_HOOKS.append(_on_activity_delete)
categories_service.CATEGORY_REASSIGN_HOOKS.append(_on_category_reassign)
