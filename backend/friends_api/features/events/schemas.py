"""Event and calendar schemas (contract section 9).

``EventRef`` and ``OccurrenceRef`` are also embedded in activity responses (``Activity.events``,
``ActivitySummary.next_occurrence``).
"""

import uuid
from datetime import date, datetime
from enum import StrEnum
from typing import Annotated

from pydantic import AwareDatetime, BaseModel, StringConstraints

from friends_api.core.schemas import ApiDate, RequestModel
from friends_api.features.events.models import EventKind
from friends_api.features.users.schemas import Timezone, UserPublic

Title = Annotated[str, StringConstraints(min_length=1, max_length=120)]
LongText = Annotated[str, StringConstraints(max_length=5000)]
LocationName = Annotated[str, StringConstraints(max_length=120)]
Address = Annotated[str, StringConstraints(max_length=300)]
RRuleText = Annotated[str, StringConstraints(max_length=200)]


class OccurrenceSource(StrEnum):
    EVENT = "event"
    MEMBER_BIRTHDAY = "member_birthday"


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


class EventWrite(RequestModel):
    """A series. Rules (contract section 5.8):

    - ``one_time``: no ``rrule``. ``recurring``: an ``rrule`` from the allowed subset (stored
      canonical). ``birthday``: all-day, ``end_date`` null or equal to ``start_date``, ``rrule``
      null or ``FREQ=YEARLY`` (29 February is allowed).
    - All-day: ``start_date`` (``end_date`` null means the same day) and no instants. Timed:
      ``starts_at`` < ``ends_at`` and no dates. At most 30 days long.
    - ``timezone`` null means the group's.
    """

    kind: EventKind
    title: Title
    description: LongText | None = None
    all_day: bool
    starts_at: AwareDatetime | None = None
    ends_at: AwareDatetime | None = None
    start_date: ApiDate | None = None
    end_date: ApiDate | None = None
    """Inclusive."""
    timezone: Timezone | None = None
    """IANA; null means the group's timezone."""
    rrule: RRuleText | None = None
    category_id: uuid.UUID | None = None
    activity_id: uuid.UUID | None = None
    """Linking an activity in ``idea`` or ``planning`` makes it ``scheduled``."""
    location_name: LocationName | None = None
    address: Address | None = None


class EventUpdate(EventWrite):
    """The complete new state of the whole series."""

    version: int
    """The version last read; a mismatch is a 409 ``version_conflict``."""


class Event(BaseModel):
    id: uuid.UUID
    group_id: uuid.UUID
    kind: EventKind
    title: str
    description: str | None
    all_day: bool
    starts_at: datetime | None
    ends_at: datetime | None
    start_date: date | None
    end_date: date | None
    """Inclusive."""
    timezone: str
    rrule: str | None
    """Canonical."""
    category_id: uuid.UUID | None
    color: str | None
    """The category's effective color."""
    activity_id: uuid.UUID | None
    location_name: str | None
    address: str | None
    cancelled_occurrence_keys: list[str]
    """Sorted."""
    version: int
    created_by: UserPublic | None
    can_edit: bool
    """Also allows cancelling and restoring occurrences."""
    can_delete: bool
    created_at: datetime
    updated_at: datetime


class Occurrence(BaseModel):
    """One calendar entry: an occurrence of an event, or a member's birthday."""

    occurrence_key: str
    source: OccurrenceSource
    event_id: uuid.UUID | None
    user_id: uuid.UUID | None
    """Member birthdays: whose birthday it is."""
    group_id: uuid.UUID | None
    """Null only for de-duplicated member birthdays in ``/me/calendar``."""
    kind: EventKind
    title: str
    """A member birthday's title is the member's display name."""
    all_day: bool
    starts_at: datetime | None
    ends_at: datetime | None
    start_date: date | None
    end_date: date | None
    """Inclusive."""
    timezone: str | None
    category_id: uuid.UUID | None
    color: str | None
    activity_id: uuid.UUID | None
    is_recurring: bool
    can_edit: bool


class CalendarResponse(BaseModel):
    from_date: date
    to_date: date
    """Exclusive."""
    tz: str
    """The zone actually used."""
    occurrences: list[Occurrence]
