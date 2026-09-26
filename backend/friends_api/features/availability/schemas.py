"""Availability schemas (contract section 13)."""

from datetime import date

from pydantic import BaseModel, Field

from friends_api.core.schemas import ApiDate, RequestModel
from friends_api.features.availability.models import AvailabilitySlot, AvailabilityStatus
from friends_api.features.users.schemas import UserPublic

MAX_RANGE_DAYS = 92
"""The longest range a request may cover."""

MAX_ENTRIES = MAX_RANGE_DAYS * len(AvailabilitySlot)

BEST_DAYS = 10
"""How many best days a group heatmap lists."""


class AvailabilityEntry(BaseModel):
    date: date
    slot: AvailabilitySlot
    status: AvailabilityStatus


class AvailabilityEntryWrite(RequestModel):
    date: ApiDate
    slot: AvailabilitySlot
    status: AvailabilityStatus


class MyAvailability(BaseModel):
    from_date: date
    to_date: date
    """Exclusive."""
    entries: list[AvailabilityEntry]
    """By date, then slot."""


class MyAvailabilityUpdate(RequestModel):
    """Replaces every entry of mine with ``from_date <= date < to_date`` by ``entries``; a slot
    left out becomes unknown."""

    from_date: ApiDate
    to_date: ApiDate
    """Exclusive; at most 92 days after ``from_date``."""
    entries: list[AvailabilityEntryWrite] = Field(default_factory=list, max_length=MAX_ENTRIES)
    """Each date within the range; one entry per date and slot."""


class SlotCounts(BaseModel):
    """How the group's current members answered for one slot of a day."""

    slot: AvailabilitySlot
    free: int
    maybe: int
    busy: int
    unknown: int
    free_users: list[UserPublic]
    """Who is free (busy stays a count only)."""
    maybe_users: list[UserPublic]


class DayAvailability(BaseModel):
    date: date
    score: float
    """free + 0.5 * maybe, for the whole day."""
    slots: list[SlotCounts]
    """all_day, then morning, afternoon and evening."""


class BestDay(BaseModel):
    date: date
    score: float
    free: int
    maybe: int
    busy: int
    unknown: int


class GroupAvailability(BaseModel):
    from_date: date
    to_date: date
    """Exclusive."""
    member_count: int
    days: list[DayAvailability]
    """Every date of the range, in order."""
    best_days: list[BestDay]
    """Up to 10 days with anyone free or maybe: highest score first, then fewer busy, then the
    earliest."""
