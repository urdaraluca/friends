"""Wheel schemas (contract sections 9 and 10)."""

import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field, field_validator

from friends_api.core.schemas import ApiDate, RequestModel
from friends_api.features.activities.models import ActivityStatus
from friends_api.features.activities.schemas import ActivitySummary
from friends_api.features.users.schemas import UserPublic

MIN_CANDIDATES = 2
MAX_CANDIDATES = 50
MAX_FILTER_STATUSES = 5

DEFAULT_WHEEL_STATUSES: tuple[ActivityStatus, ...] = (ActivityStatus.IDEA, ActivityStatus.PLANNING)
"""The wheel's pool is the active backlog unless asked otherwise (``list_activities`` also
shows ``scheduled`` by default)."""


class WheelFilters(RequestModel):
    """Which activities go on the wheel; the same semantics as ``list_activities``. There is no
    server default for ``interested_by``: the client's "Only ideas I'm interested in" toggle
    starts on and sends it."""

    # The default is applied by the validator below rather than declared in the schema: the
    # generated Dart client can't express an enum-list default (it emits code that doesn't
    # compile). Omitted and null both mean the default (contract section 1.4).
    status: list[ActivityStatus] = Field(
        default_factory=lambda: list(DEFAULT_WHEEL_STATUSES),
        min_length=1,
        max_length=MAX_FILTER_STATUSES,
        description="1..5 statuses. Omitted or null: idea and planning.",
    )
    category_id: uuid.UUID | None = None
    include_subcategories: bool = True
    """With ``category_id``: also its subcategories."""
    interested_by: uuid.UUID | None = None
    owner_id: uuid.UUID | None = None
    cost_max: int | None = Field(default=None, ge=0)
    """``estimated_cost <= cost_max`` in the group's currency."""
    include_unpriced: bool = True
    """With ``cost_max``: also activities without a cost or in another currency."""
    due_before: ApiDate | None = None
    """``due_date <= due_before`` (inclusive); activities without a due date are excluded."""

    @field_validator("status", mode="before")
    @classmethod
    def _null_status_is_the_default(cls, value: Any) -> Any:
        return list(DEFAULT_WHEEL_STATUSES) if value is None else value


class WheelCandidates(BaseModel):
    items: list[ActivitySummary]
    """The first 50 of the pool, newest first."""
    total: int
    """The size of the whole pool."""


class SpinCreate(RequestModel):
    filters: WheelFilters
    """Without ``activity_ids`` they select the pool; with them they are only stored for
    display."""
    activity_ids: list[uuid.UUID] | None = Field(default=None, max_length=MAX_CANDIDATES)
    """A hand-picked subset of this group's activities, in slice order. Duplicates are ignored
    (the first keeps its position); fewer than 2 distinct is a 422 ``not_enough_candidates``."""


class WheelCandidate(BaseModel):
    """A slice of the wheel, as it was at spin time."""

    id: uuid.UUID
    title: str
    category_id: uuid.UUID | None
    color: str | None
    """The category's effective color at spin time."""


class WheelSpin(BaseModel):
    id: uuid.UUID
    group_id: uuid.UUID
    spun_by: UserPublic | None
    filters: WheelFilters
    candidates: list[WheelCandidate]
    """In slice order."""
    result_index: int
    result: WheelCandidate
    """``candidates[result_index]``."""
    result_activity_id: uuid.UUID | None
    """Null once the activity is deleted."""
    accepted_at: datetime | None
    accepted_by: UserPublic | None
    created_at: datetime


class WheelSpinPage(BaseModel):
    items: list[WheelSpin]
    next_cursor: str | None
