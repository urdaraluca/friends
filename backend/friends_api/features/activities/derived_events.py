"""Calendar values shown on activities: ``ActivitySummary.next_occurrence`` and
``Activity.events`` (contract sections 5.8 and 9).

Batched: one query per page of activities, never one per row.
"""

import uuid
from collections.abc import Sequence
from datetime import datetime, time

from sqlalchemy import select
from sqlalchemy.orm import Session

from friends_api.features.activities.models import Activity
from friends_api.features.events.lookup import cancelled_keys, zone
from friends_api.features.events.models import Event
from friends_api.features.events.recurrence import next_occurrence
from friends_api.features.events.schemas import EventRef, OccurrenceRef
from friends_api.features.groups.models import Group


def next_occurrences(
    db: Session, activities: Sequence[Activity], *, now: datetime
) -> dict[uuid.UUID, OccurrenceRef]:
    """The first occurrence that hasn't ended, across each activity's linked events, by
    activity ID; activities without one are left out. Timed occurrences end after ``now``;
    all-day ones end on or after today in the group's timezone. Cancelled occurrences don't
    count."""
    ids = [activity.id for activity in activities]
    if not ids:
        return {}
    events = db.scalars(select(Event).where(Event.activity_id.in_(ids))).all()
    if not events:
        return {}
    cancelled = cancelled_keys(db, (event.id for event in events))
    zones = {
        group_id: zone(name)
        for group_id, name in db.execute(
            select(Group.id, Group.timezone).where(
                Group.id.in_({event.group_id for event in events})
            )
        )
    }
    best: dict[uuid.UUID, tuple[datetime, bool, OccurrenceRef]] = {}
    for event in events:
        assert event.activity_id is not None  # noqa: S101 - selected by activity_id
        group_zone = zones[event.group_id]
        span = next_occurrence(
            event.series(),
            now=now,
            today=now.astimezone(group_zone).date(),
            cancelled=cancelled.get(event.id, ()),
        )
        if span is None:
            continue
        if span.starts_at is not None:
            order = (span.starts_at, True)
        else:
            assert span.start_date is not None  # noqa: S101 - an all-day span
            order = (datetime.combine(span.start_date, time(), group_zone), False)
        ref = OccurrenceRef(
            event_id=event.id,
            occurrence_key=span.key,
            all_day=span.all_day,
            starts_at=span.starts_at,
            start_date=span.start_date,
        )
        current = best.get(event.activity_id)
        if current is None or order < current[:2]:
            best[event.activity_id] = (*order, ref)
    return {activity_id: ref for activity_id, (_, _, ref) in best.items()}


def linked_events(db: Session, activity: Activity) -> list[EventRef]:
    """The activity's linked events, by ``window_start``."""
    events = db.scalars(
        select(Event).where(Event.activity_id == activity.id).order_by(Event.window_start, Event.id)
    )
    return [
        EventRef(
            id=event.id,
            kind=event.kind,
            title=event.title,
            all_day=event.all_day,
            starts_at=event.starts_at,
            start_date=event.start_date,
            rrule=event.rrule,
        )
        for event in events
    ]
