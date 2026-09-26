"""Polls inside activities (contract sections 3.1 and 8.9).

Cut from the MVP: anonymous polls, ``max_choices`` and ``allow_member_options`` (any member may
add options).
"""

import uuid
from datetime import datetime

from sqlalchemy import ColumnElement, ForeignKey, Index, String, UniqueConstraint, and_, or_
from sqlalchemy.orm import Mapped, mapped_column

from friends_api.core.db import Base, IdMixin, TimestampMixin, utcnow

MAX_POLLS_PER_ACTIVITY = 10
MIN_OPTIONS, MAX_OPTIONS = 2, 20
MAX_VOTE_OPTION_IDS = 20


class Poll(IdMixin, TimestampMixin, Base):
    __tablename__ = "polls"

    group_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("groups.id", ondelete="CASCADE"), index=True
    )
    """Copied from the activity."""
    activity_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("activities.id", ondelete="CASCADE"), index=True
    )
    question: Mapped[str] = mapped_column(String(200))
    allow_multiple: Mapped[bool] = mapped_column(default=False)
    """Fixed at creation."""
    closes_at: Mapped[datetime | None]
    """Automatic close: the poll counts as closed once this has passed."""
    closed_at: Mapped[datetime | None]
    """Manual close."""
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), index=True
    )

    def is_open(self, now: datetime) -> bool:
        """Computed on read, never stored: GET handlers don't write."""
        return self.closed_at is None and (self.closes_at is None or self.closes_at > now)

    @staticmethod
    def open_clause(now: datetime) -> ColumnElement[bool]:
        """``is_open`` as SQL: ``closed_at IS NULL AND (closes_at IS NULL OR closes_at > now)``."""
        return and_(Poll.closed_at.is_(None), or_(Poll.closes_at.is_(None), Poll.closes_at > now))


class PollOption(IdMixin, Base):
    __tablename__ = "poll_options"
    # The NOCASE collation of `label` makes the unique constraint case-insensitive.
    __table_args__ = (UniqueConstraint("poll_id", "label"),)

    poll_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("polls.id", ondelete="CASCADE"))
    label: Mapped[str] = mapped_column(String(100, collation="NOCASE"))
    url: Mapped[str | None] = mapped_column(String(2048))
    position: Mapped[int]
    """Display order; a new option goes last. Deleting one leaves a gap."""
    added_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), index=True
    )
    created_at: Mapped[datetime] = mapped_column(default=utcnow)


class PollVote(Base):
    """One member's vote for one option; a multiple-choice vote is several rows."""

    __tablename__ = "poll_votes"
    __table_args__ = (Index("ix_poll_votes_poll_user", "poll_id", "user_id"),)

    option_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("poll_options.id", ondelete="CASCADE"), primary_key=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True
    )
    poll_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("polls.id", ondelete="CASCADE"))
    """Denormalized from the option, for per-poll queries."""
    created_at: Mapped[datetime] = mapped_column(default=utcnow)
