"""Event schemas (contract section 9).

M6 defines the two small references that activity responses embed. TODO(#12): the event and
calendar schemas (``Event``, ``EventWrite``, ``Occurrence``, ...) go here too.
"""

import uuid
from datetime import date, datetime

from pydantic import BaseModel

from friends_api.features.events.models import EventKind


class EventRef(BaseModel):
    """A calendar event linked to an activity (``Activity.events``, by ``window_start``)."""

    id: uuid.UUID
    kind: EventKind
    title: str
    all_day: bool
    starts_at: datetime | None
    start_date: date | None
    rrule: str | None


class OccurrenceRef(BaseModel):
    """The next occurrence of an activity's linked events (``ActivitySummary.next_occurrence``)."""

    event_id: uuid.UUID
    occurrence_key: str
    all_day: bool
    starts_at: datetime | None
    start_date: date | None
