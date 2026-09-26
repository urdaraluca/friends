"""Batched lookups around events: one query for a whole list, never one per row.

Used by the events service, the calendar and the activities feature (next occurrence, linked
events), so this module imports no service.
"""

import uuid
from collections import defaultdict
from collections.abc import Iterable
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from friends_api.features.activities.models import Activity
from friends_api.features.events.models import EventException
from friends_api.features.users.schemas import is_valid_timezone


def cancelled_keys(db: Session, event_ids: Iterable[uuid.UUID]) -> dict[uuid.UUID, set[str]]:
    """The cancelled occurrence keys by event ID (events without any are left out)."""
    wanted = set(event_ids)
    if not wanted:
        return {}
    keys: defaultdict[uuid.UUID, set[str]] = defaultdict(set)
    rows = db.execute(
        select(EventException.event_id, EventException.occurrence_key).where(
            EventException.event_id.in_(wanted)
        )
    )
    for event_id, key in rows:
        keys[event_id].add(key)
    return dict(keys)


def activity_owners(
    db: Session, activity_ids: Iterable[uuid.UUID | None]
) -> dict[uuid.UUID, uuid.UUID | None]:
    """The owner of each linked activity, by activity ID (for the event permission rule)."""
    wanted = {activity_id for activity_id in activity_ids if activity_id is not None}
    if not wanted:
        return {}
    rows = db.execute(select(Activity.id, Activity.owner_id).where(Activity.id.in_(wanted)))
    return {activity_id: owner_id for activity_id, owner_id in rows}  # noqa: C416 - Row


def zone(name: str | None) -> ZoneInfo:
    """``ZoneInfo(name)``, or UTC for a missing or unknown name (stored names are validated;
    this only guards reads)."""
    return ZoneInfo(name if name and is_valid_timezone(name) else "UTC")
