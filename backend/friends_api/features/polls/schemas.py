"""Poll schemas (contract section 9)."""

import uuid
from datetime import UTC, datetime
from typing import Annotated

from pydantic import AfterValidator, AwareDatetime, BaseModel, Field, StringConstraints

from friends_api.core.schemas import HttpUrlStr, RequestModel
from friends_api.features.polls.models import MAX_OPTIONS, MAX_VOTE_OPTION_IDS, MIN_OPTIONS
from friends_api.features.users.schemas import UserPublic

Question = Annotated[str, StringConstraints(min_length=1, max_length=200)]
OptionLabel = Annotated[str, StringConstraints(min_length=1, max_length=100)]


def _to_utc(value: datetime) -> datetime:
    return value.astimezone(UTC)


UtcInstant = Annotated[AwareDatetime, AfterValidator(_to_utc)]
"""Any UTC offset is accepted and converted to UTC; a value without an offset gets 422."""


class PollOptionCreate(RequestModel):
    label: OptionLabel
    """Unique within the poll, case-insensitively."""
    url: HttpUrlStr | None = None


class PollCreate(RequestModel):
    question: Question
    allow_multiple: bool = False
    """Fixed at creation."""
    closes_at: UtcInstant | None = None
    """Must be in the future; the poll closes by itself then."""
    options: list[PollOptionCreate] = Field(min_length=MIN_OPTIONS, max_length=MAX_OPTIONS)
    """2 to 20, with labels unique case-insensitively."""


class PollUpdate(RequestModel):
    """The complete new state (``allow_multiple`` can't change)."""

    question: Question
    closes_at: UtcInstant | None = None
    """Must be in the future, unless it is the stored value sent back unchanged."""


class VoteRequest(RequestModel):
    option_ids: list[uuid.UUID] = Field(max_length=MAX_VOTE_OPTION_IDS)
    """The caller's complete vote: replaces any earlier one. Empty retracts it; duplicates are
    ignored. At most one on a single-choice poll."""


class PollOption(BaseModel):
    id: uuid.UUID
    label: str
    url: str | None
    position: int
    vote_count: int
    voters: list[UserPublic]
    """In the order they voted."""
    added_by: UserPublic | None
    can_delete: bool
    """Whoever added it (while it has no votes) or the poll's manager. Deleting also needs at
    least 3 options, so that 2 remain."""


class Poll(BaseModel):
    id: uuid.UUID
    group_id: uuid.UUID
    activity_id: uuid.UUID
    question: str
    allow_multiple: bool
    closes_at: datetime | None
    closed_at: datetime | None
    is_open: bool
    """``closed_at`` is null and ``closes_at`` is null or still in the future."""
    options: list[PollOption]
    """By position."""
    my_option_ids: list[uuid.UUID]
    """The caller's vote, in option order; empty when they haven't voted."""
    total_voters: int
    """Distinct members who voted."""
    winning_option_ids: list[uuid.UUID]
    """The options with the most votes (several on a tie); empty while nobody has voted."""
    created_by: UserPublic | None
    can_manage: bool
    """Edit, close, reopen or delete: the poll's creator, the activity's owner or an admin+."""
    created_at: datetime
    updated_at: datetime
