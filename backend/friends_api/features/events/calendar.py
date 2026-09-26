"""Calendar queries (contract section 5.5): ``GET /groups/{group_id}/calendar`` and
``GET /me/calendar``.

Events are prefiltered in SQL on their search window, then expanded and filtered exactly in
Python. Member birthdays are virtual occurrences built from profiles.
"""

import uuid
from collections.abc import Collection, Iterable, Mapping
from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import Any
from zoneinfo import ZoneInfo

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from friends_api.core.errors import FieldError, Unprocessable
from friends_api.features.auth.models import User
from friends_api.features.categories.models import Category
from friends_api.features.categories.service import CategoryIndex
from friends_api.features.events import policies, recurrence
from friends_api.features.events.lookup import activity_owners, cancelled_keys
from friends_api.features.events.models import Event, EventKind
from friends_api.features.events.schemas import CalendarResponse, Occurrence, OccurrenceSource
from friends_api.features.groups.models import Membership
from friends_api.features.groups.service import GroupAccess
from friends_api.features.users.schemas import is_valid_timezone

MAX_RANGE_DAYS = 400
_NO_INSTANT = datetime.min.replace(tzinfo=UTC)


@dataclass(frozen=True, slots=True, kw_only=True)
class CalendarQuery:
    from_date: date
    to_date: date
    """Exclusive."""
    tz: str | None = None
    """IANA; missing or invalid means the caller's own timezone."""
    kinds: Collection[EventKind] | None = None
    """``None`` or empty: every kind. ``birthday`` covers member birthdays too."""
    category_id: uuid.UUID | None = None
    """Group calendar only: that category and its subcategories; excludes member birthdays."""


def _range_error(field: str, message: str, code: str = "validation_error") -> Unprocessable:
    type_ = "value_error" if code == "validation_error" else code
    return Unprocessable(
        message, code=code, errors=[FieldError(field=field, message=message, type=type_)]
    )


def _calendar_range(query: CalendarQuery, user: User) -> recurrence.Range:
    if query.to_date <= query.from_date:
        raise _range_error("query.to", "`to` must be after `from`.")
    if (query.to_date - query.from_date).days > MAX_RANGE_DAYS:
        raise _range_error(
            "query.to",
            f"The range is at most {MAX_RANGE_DAYS} days.",
            code="range_too_large",
        )
    for field, day in (("query.from", query.from_date), ("query.to", query.to_date)):
        if not recurrence.MIN_DATE <= day <= recurrence.MAX_DATE:
            raise _range_error(field, "Use a date between the years 1000 and 8999.")
    return recurrence.Range.in_zone(query.from_date, query.to_date, _zone_name(query.tz, user))


def _zone_name(requested: str | None, user: User) -> str:
    """The requested zone if valid, else the caller's own (section 1.3)."""
    for name in (requested, user.timezone):
        if name and is_valid_timezone(name):
            return name
    return "UTC"


def _kinds(query: CalendarQuery) -> set[EventKind]:
    return set(query.kinds) if query.kinds else set(EventKind)


def _with_subcategories(db: Session, group_id: uuid.UUID, category_id: uuid.UUID) -> list[Any]:
    children = db.scalars(
        select(Category.id).where(Category.group_id == group_id, Category.parent_id == category_id)
    )
    return [category_id, *children]


def _event_occurrences(
    db: Session,
    memberships: Mapping[uuid.UUID, Membership],
    in_range: recurrence.Range,
    kinds: set[EventKind],
    category_ids: list[Any] | None,
) -> list[Occurrence]:
    """The occurrences of the events of ``memberships``' groups (by group ID)."""
    if not memberships:
        return []
    stmt = select(Event).where(
        Event.group_id.in_(memberships),
        Event.kind.in_(kinds),
        Event.window_start < in_range.end,
        or_(Event.window_end.is_(None), Event.window_end > in_range.start),
    )
    if category_ids is not None:
        stmt = stmt.where(Event.category_id.in_(category_ids))
    events = db.scalars(stmt).all()
    if not events:
        return []
    cancelled = cancelled_keys(db, (event.id for event in events))
    owners = activity_owners(db, (event.activity_id for event in events))
    index = CategoryIndex(db.scalars(select(Category).where(Category.group_id.in_(memberships))))
    occurrences: list[Occurrence] = []
    for event in events:
        owner_id = owners.get(event.activity_id) if event.activity_id else None
        can_edit = policies.can_edit_event(memberships[event.group_id], event, owner_id)
        color = index.effective_color(event.category_id)
        spans = recurrence.expand(event.series(), in_range, cancelled=cancelled.get(event.id, ()))
        occurrences.extend(
            Occurrence(
                occurrence_key=span.key,
                source=OccurrenceSource.EVENT,
                event_id=event.id,
                user_id=None,
                group_id=event.group_id,
                kind=event.kind,
                title=event.title,
                all_day=span.all_day,
                starts_at=span.starts_at,
                ends_at=span.ends_at,
                start_date=span.start_date,
                end_date=span.end_date,
                timezone=event.timezone,
                category_id=event.category_id,
                color=color,
                activity_id=event.activity_id,
                is_recurring=event.kind is not EventKind.ONE_TIME,
                can_edit=can_edit,
            )
            for span in spans
        )
    return occurrences


def _member_birthdays(
    db: Session,
    group_ids: Iterable[uuid.UUID],
    in_range: recurrence.Range,
    *,
    group_id: uuid.UUID | None,
) -> list[Occurrence]:
    """Section 5.7: current members of ``group_ids`` with a birthday and ``show_birthday`` on
    in at least one of them, once per person. The year is never exposed."""
    users = db.scalars(
        select(User)
        .join(Membership, Membership.user_id == User.id)
        .where(
            Membership.group_id.in_(list(group_ids)),
            Membership.show_birthday.is_(True),
            User.deleted_at.is_(None),
            User.birthday_month.is_not(None),
            User.birthday_day.is_not(None),
        )
        .distinct()
    ).all()
    occurrences: list[Occurrence] = []
    for user in users:
        assert user.birthday_month is not None  # noqa: S101 - filtered above
        assert user.birthday_day is not None  # noqa: S101
        try:
            days = recurrence.birthday_dates(
                user.birthday_month, user.birthday_day, None, in_range.from_date, in_range.to_date
            )
        except ValueError:  # an impossible stored date (the service validates): skip it
            continue
        occurrences.extend(
            Occurrence(
                occurrence_key=recurrence.date_key(day),
                source=OccurrenceSource.MEMBER_BIRTHDAY,
                event_id=None,
                user_id=user.id,
                group_id=group_id,
                kind=EventKind.BIRTHDAY,
                title=user.display_name,
                all_day=True,
                starts_at=None,
                ends_at=None,
                start_date=day,
                end_date=day,
                timezone=None,
                category_id=None,
                color=None,
                activity_id=None,
                is_recurring=True,
                can_edit=False,
            )
            for day in days
        )
    return occurrences


def _sorted(occurrences: list[Occurrence], tz: ZoneInfo) -> list[Occurrence]:
    """Local start date in ``tz``, all-day before timed, start instant, title, key."""

    def key(occurrence: Occurrence) -> tuple[Any, ...]:
        if occurrence.starts_at is None:
            first_day, instant = occurrence.start_date, _NO_INSTANT
        else:
            first_day, instant = occurrence.starts_at.astimezone(tz).date(), occurrence.starts_at
        return (
            first_day,
            not occurrence.all_day,
            instant,
            occurrence.title.casefold(),
            occurrence.title,
            occurrence.occurrence_key,
            str(occurrence.event_id or occurrence.user_id),
        )

    return sorted(occurrences, key=key)


def _response(
    query: CalendarQuery, in_range: recurrence.Range, tz: str, occurrences: list[Occurrence]
) -> CalendarResponse:
    return CalendarResponse(
        from_date=query.from_date,
        to_date=query.to_date,
        tz=tz,
        occurrences=_sorted(occurrences, ZoneInfo(tz)),
    )


def group_calendar(
    db: Session, access: GroupAccess, user: User, query: CalendarQuery
) -> CalendarResponse:
    """The group's events and its members' birthdays in ``[from, to)``."""
    in_range = _calendar_range(query, user)
    tz, group_id, kinds = _zone_name(query.tz, user), access.group.id, _kinds(query)
    category_ids = (
        _with_subcategories(db, group_id, query.category_id)
        if query.category_id is not None
        else None
    )
    occurrences = _event_occurrences(
        db, {group_id: access.membership}, in_range, kinds, category_ids
    )
    if EventKind.BIRTHDAY in kinds and query.category_id is None:
        occurrences += _member_birthdays(db, [group_id], in_range, group_id=group_id)
    return _response(query, in_range, tz, occurrences)


def my_calendar(db: Session, user: User, query: CalendarQuery) -> CalendarResponse:
    """The events of all my groups, and the birthdays of the people I share a group with (once
    each, with ``group_id = null``) when they show it in at least one of those groups."""
    in_range = _calendar_range(query, user)
    tz, kinds = _zone_name(query.tz, user), _kinds(query)
    memberships = {
        membership.group_id: membership
        for membership in db.scalars(select(Membership).where(Membership.user_id == user.id))
    }
    occurrences = _event_occurrences(db, memberships, in_range, kinds, None)
    if EventKind.BIRTHDAY in kinds and memberships:
        occurrences += _member_birthdays(db, memberships, in_range, group_id=None)
    return _response(query, in_range, tz, occurrences)
