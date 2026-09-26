import math
import uuid
from datetime import date, datetime
from enum import StrEnum
from typing import Annotated, Any

from pydantic import BaseModel, Field, StringConstraints, model_validator

from friends_api.core.schemas import ApiDate, Currency, HttpUrlStr, RequestModel
from friends_api.features.activities.models import MAX_ESTIMATED_COST, ActivityStatus
from friends_api.features.categories.schemas import FieldKey, FieldType
from friends_api.features.events.schemas import EventRef, OccurrenceRef
from friends_api.features.users.schemas import UserPublic

MAX_LINKS = 10

Title = Annotated[str, StringConstraints(min_length=1, max_length=120)]
LongText = Annotated[str, StringConstraints(max_length=5000)]
LocationName = Annotated[str, StringConstraints(max_length=120)]
Address = Annotated[str, StringConstraints(max_length=300)]


class ActivitySort(StrEnum):
    CREATED_AT = "created_at"
    DUE_DATE = "due_date"
    TITLE = "title"
    INTEREST_COUNT = "interest_count"
    ESTIMATED_COST = "estimated_cost"


class SortOrder(StrEnum):
    ASC = "asc"
    DESC = "desc"


class Link(RequestModel):
    url: HttpUrlStr
    label: Annotated[str, StringConstraints(max_length=60)] | None = None


class CardAttribute(BaseModel):
    """A custom-field value shown on the backlog card (its definition has ``show_on_card``)."""

    key: str
    label: str
    type: FieldType
    value: Any
    """A string or a number."""


class ActivitySummary(BaseModel):
    id: uuid.UUID
    group_id: uuid.UUID
    title: str
    status: ActivityStatus
    category_id: uuid.UUID | None
    owner: UserPublic | None
    due_date: date | None
    estimated_cost: int | None
    currency: str | None
    cost_per_person: bool
    interest_count: int
    i_am_interested: bool
    poll_count: int
    open_poll_count: int
    my_unvoted_poll_count: int
    """Open polls without a vote from the caller (the card's "Vote" badge)."""
    card_attributes: list[CardAttribute]
    next_occurrence: OccurrenceRef | None
    can_edit: bool
    can_delete: bool
    created_at: datetime
    updated_at: datetime


class Activity(ActivitySummary):
    description: str | None
    notes: str | None
    location_name: str | None
    address: str | None
    links: list[Link]
    attributes: dict[str, Any]
    """Custom-field values (key -> string or number) that match the current definitions."""
    interested_users: list[UserPublic]
    created_by: UserPublic | None
    status_changed_at: datetime
    completed_at: datetime | None
    version: int
    events: list[EventRef]
    """Linked calendar events, by start."""


class ActivityWrite(RequestModel):
    title: Title
    description: LongText | None = None
    notes: LongText | None = None
    category_id: uuid.UUID | None = None
    owner_id: uuid.UUID | None = None
    due_date: ApiDate | None = None
    estimated_cost: int | None = Field(default=None, ge=0, le=MAX_ESTIMATED_COST)
    """Whole currency units."""
    currency: Currency | None = None
    """With a cost, null means the group's currency; without a cost it is ignored."""
    cost_per_person: bool = True
    location_name: LocationName | None = None
    address: Address | None = None
    links: list[Link] = Field(default_factory=list, max_length=MAX_LINKS)
    attributes: dict[str, Any] = Field(default_factory=dict)
    """Custom-field values for the category's effective field definitions. ``null`` or ``""``
    clears a key."""


class ActivityCreate(ActivityWrite):
    """``owner_id: null`` means the creator."""

    status: ActivityStatus = ActivityStatus.IDEA


class ActivityUpdate(ActivityWrite):
    """The complete new state. ``owner_id: null`` means unowned."""

    version: int
    """The version last read; a mismatch is a 409 ``version_conflict``."""


class StatusChange(RequestModel):
    status: ActivityStatus


class InterestState(BaseModel):
    activity_id: uuid.UUID
    interested: bool
    interest_count: int
    interested_users: list[UserPublic]


class ActivityPage(BaseModel):
    items: list[ActivitySummary]
    next_cursor: str | None


MAX_ATTRIBUTE_FILTERS = 5
"""The most attribute filters one request may combine."""


class AttributeOp(StrEnum):
    EQ = "eq"
    """Text equal (ASCII case-insensitive), or number equal when ``value`` is one."""
    CONTAINS = "contains"
    """Text contains (ASCII case-insensitive)."""
    GTE = "gte"
    """Number at least ``value``."""
    LTE = "lte"
    """Number at most ``value``."""


def as_number(value: str) -> float | None:
    """``value`` as a finite number, or None."""
    try:
        number = float(value)
    except ValueError:
        return None
    return number if math.isfinite(number) else None


class AttributeFilter(RequestModel):
    """Matches activities whose custom attribute ``key`` (contract section 6) satisfies ``op``.
    An activity without the attribute, or with a value of another type, never matches."""

    key: FieldKey
    op: AttributeOp
    value: str = Field(min_length=1, max_length=100)

    @model_validator(mode="after")
    def _numbers_for_comparisons(self) -> AttributeFilter:
        if self.op in (AttributeOp.GTE, AttributeOp.LTE) and as_number(self.value) is None:
            raise ValueError("gte and lte need a number.")
        return self


def parse_attribute_filter(raw: str) -> AttributeFilter:
    """``key:op:value`` (the value may contain ``:``); ``ValueError`` when malformed."""
    parts = raw.split(":", 2)
    if len(parts) != 3:
        raise ValueError("Use key:op:value, e.g. imdb_rating:gte:7.5.")
    key, op, value = parts
    return AttributeFilter.model_validate({"key": key, "op": op, "value": value})
