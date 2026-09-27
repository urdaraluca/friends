"""Batched lookups around events: one query for a whole list, never one per row.

Used by the events service, the calendar and the activities feature (next occurrence, linked
events), so this module imports no service.
"""

import uuid
from collections import defaultdict
from collections.abc import Iterable
from dataclasses import dataclass, field
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from friends_api.features.activities.models import Activity
from friends_api.features.events.models import EventException
from friends_api.features.events.recurrence import Override
from friends_api.features.users.schemas import is_valid_timezone


@dataclass(slots=True)
class Exceptions:
    """One event's exceptions (section 5.6): cancelled keys and edited occurrences."""

    cancelled: set[str] = field(default_factory=set)
    edits: dict[str, EventException] = field(default_factory=dict)
    """By occurrence key."""

    def overrides(self) -> dict[str, Override]:
        return {key: row.override() for key, row in self.edits.items()}


NO_EXCEPTIONS = Exceptions()


def event_exceptions(db: Session, event_ids: Iterable[uuid.UUID]) -> dict[uuid.UUID, Exceptions]:
    """The exceptions by event ID (events without any are left out)."""
    wanted = set(event_ids)
    if not wanted:
        return {}
    result: defaultdict[uuid.UUID, Exceptions] = defaultdict(Exceptions)
    for row in db.scalars(select(EventException).where(EventException.event_id.in_(wanted))):
        if row.cancelled:
            result[row.event_id].cancelled.add(row.occurrence_key)
        else:
            result[row.event_id].edits[row.occurrence_key] = row
    return dict(result)


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
