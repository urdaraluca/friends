"""Calendar events (contract sections 3.1 and 5).

An event row is a *series*: occurrences are computed on read (``recurrence.expand``), and
``event_exceptions`` cancels single occurrences.
"""

import uuid
from datetime import date, datetime
from enum import StrEnum

from sqlalchemy import CheckConstraint, ForeignKey, Index, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from friends_api.core.db import Base, IdMixin, TimestampMixin, str_enum, utcnow
from friends_api.features.events.recurrence import Series


class EventKind(StrEnum):
    ONE_TIME = "one_time"
    RECURRING = "recurring"
    BIRTHDAY = "birthday"


class Event(IdMixin, TimestampMixin, Base):
    """A calendar series of a group: one-time, recurring, or a birthday of someone who isn't
    on the app."""

    __tablename__ = "events"
    __table_args__ = (
        CheckConstraint(
            "(all_day AND start_date IS NOT NULL AND end_date IS NOT NULL"
            " AND starts_at IS NULL AND ends_at IS NULL)"
            " OR (NOT all_day AND starts_at IS NOT NULL AND ends_at IS NOT NULL"
            " AND start_date IS NULL AND end_date IS NULL)",
            name="timing",
        ),
        CheckConstraint("(kind = 'one_time') = (rrule IS NULL)", name="kind_rrule"),
        CheckConstraint(
            "kind <> 'birthday' OR (all_day AND rrule = 'FREQ=YEARLY' AND end_date = start_date)",
            name="birthday",
        ),
        Index("ix_events_group_window_start", "group_id", "window_start"),
        Index("ix_events_group_window_end", "group_id", "window_end"),
    )

    group_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("groups.id", ondelete="CASCADE"))
    kind: Mapped[EventKind] = mapped_column(str_enum(EventKind, 10))
    title: Mapped[str] = mapped_column(String(120))
    description: Mapped[str | None] = mapped_column(Text)
    category_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("categories.id", ondelete="SET NULL"), index=True
    )
    activity_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("activities.id", ondelete="SET NULL"), index=True
    )
    """A scheduled backlog item. Deleting the activity nulls it with ``version + 1`` (the
    service does; the FK's SET NULL is a safety net)."""
    all_day: Mapped[bool]
    starts_at: Mapped[datetime | None]
    """Timed: the start instant of the first occurrence."""
    ends_at: Mapped[datetime | None]
    """Timed: the end instant of the first occurrence."""
    start_date: Mapped[date | None]
    """All-day: the first day of the first occurrence."""
    end_date: Mapped[date | None]
    """All-day: the last day of the first occurrence (inclusive)."""
    timezone: Mapped[str] = mapped_column(String(64))
    """The wall clock used for expansion (the group's unless the event says otherwise)."""
    rrule: Mapped[str | None] = mapped_column(String(200))
    """Canonical restricted RRULE without DTSTART (contract section 5.2); ``FREQ=YEARLY`` for
    birthdays; null for one-time events."""
    location_name: Mapped[str | None] = mapped_column(String(120))
    address: Mapped[str | None] = mapped_column(String(300))
    window_start: Mapped[datetime]
    """Computed superset search window (contract section 5.4)."""
    window_end: Mapped[datetime | None]
    """Null: the series never ends."""
    version: Mapped[int] = mapped_column(default=1)
    """Optimistic lock: bumped by every PUT and every server-side change to a written field."""
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), index=True
    )

    def series(self) -> Series:
        """What ``recurrence`` needs to expand this event."""
        return Series(
            kind=self.kind.value,
            all_day=self.all_day,
            starts_at=self.starts_at,
            ends_at=self.ends_at,
            start_date=self.start_date,
            end_date=self.end_date,
            timezone=self.timezone,
            rrule=self.rrule,
        )


class EventException(IdMixin, Base):
    """Cancels one occurrence of a series (MVP; single-occurrence edits come later)."""

    __tablename__ = "event_exceptions"
    __table_args__ = (UniqueConstraint("event_id", "occurrence_key"),)

    event_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("events.id", ondelete="CASCADE"))
    occurrence_key: Mapped[str] = mapped_column(String(20))
    """``20261001T160000Z`` (timed) or ``20261001`` (all-day and birthdays)."""
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), index=True
    )
    created_at: Mapped[datetime] = mapped_column(default=utcnow)
