"""Recap schemas (contract section 14)."""

import uuid
from datetime import date, datetime
from enum import StrEnum

from pydantic import BaseModel

from friends_api.features.users.schemas import UserPublic

MAX_MEMORIES = 100
"""How many memories a recap lists (all are counted)."""

TOP_PLANNERS = 3
TOP_CATEGORIES = 3

EARLIEST_YEAR = 2000
"""Recaps start in this year at the earliest."""


class RecapPeriod(StrEnum):
    MONTH = "month"
    YEAR = "year"


class RecapActivity(BaseModel):
    id: uuid.UUID
    title: str
    category_id: uuid.UUID | None
    color: str | None
    """The category's effective colour."""
    created_at: datetime
    completed_at: datetime


class RecapPlanner(BaseModel):
    user: UserPublic
    score: int
    """``ideas + events + polls + done``."""
    ideas: int
    """Activities created."""
    events: int
    """Events created."""
    polls: int
    """Polls created."""
    done: int
    """Activities marked done."""


class RecapCategory(BaseModel):
    """A top-level category and how many memories fall under it (its subcategories
    included)."""

    id: uuid.UUID
    name: str
    color: str | None
    icon: str | None
    count: int


class RecapPoll(BaseModel):
    id: uuid.UUID
    question: str
    activity_id: uuid.UUID
    activity_title: str
    voters: int


class RecapWait(BaseModel):
    activity: RecapActivity
    days: int
    """Whole days from ``created_at`` to ``completed_at``."""


class RecapMonth(BaseModel):
    month: date
    """The first day of the month."""
    count: int


class RecapIdea(BaseModel):
    activity_id: uuid.UUID
    title: str
    color: str | None
    interested: int


class Recap(BaseModel):
    period: RecapPeriod
    start: date
    end: date
    """Exclusive: the start of the next period."""
    timezone: str
    """The group's; the period's days are in it."""
    complete: bool
    """False while the period is still running."""
    memory_count: int
    """Activities completed in the period."""
    memories: list[RecapActivity]
    """By ``completed_at``; the first 100."""
    planners: list[RecapPlanner]
    """The 3 most active, by score, then name."""
    top_categories: list[RecapCategory]
    """The 3 top-level categories with the most memories."""
    ideas_added: int
    events_planned: int
    polls_created: int
    wheel_decisions: int
    """Wheel spins accepted ("Let's do it!")."""
    new_members: int
    top_poll: RecapPoll | None
    """The poll created in the period with the most voters."""
    longest_wait: RecapWait | None
    """The memory that waited longest to happen."""
    busiest_month: RecapMonth | None
    """For a year: the month with the most memories."""
    most_wanted: RecapIdea | None
    """The idea still in the backlog (idea or planning today) with the most interest by the
    end of the period."""
