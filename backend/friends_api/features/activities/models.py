import uuid
from datetime import date, datetime
from enum import StrEnum
from typing import Any

from sqlalchemy import JSON, CheckConstraint, ForeignKey, Index, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from friends_api.core.db import Base, IdMixin, TimestampMixin, str_enum, utcnow

MAX_ESTIMATED_COST = 10_000_000


class ActivityStatus(StrEnum):
    IDEA = "idea"
    PLANNING = "planning"
    SCHEDULED = "scheduled"
    DONE = "done"
    DROPPED = "dropped"


class Activity(IdMixin, TimestampMixin, Base):
    """A backlog item of a group."""

    __tablename__ = "activities"
    __table_args__ = (
        CheckConstraint(
            f"estimated_cost IS NULL OR estimated_cost BETWEEN 0 AND {MAX_ESTIMATED_COST}",
            name="cost_range",
        ),
        CheckConstraint("(estimated_cost IS NULL) = (currency IS NULL)", name="cost_currency"),
        Index("ix_activities_group_status_created", "group_id", "status", "created_at"),
        Index("ix_activities_group_category", "group_id", "category_id"),
        Index("ix_activities_group_owner", "group_id", "owner_id"),
        Index("ix_activities_group_due_date", "group_id", "due_date"),
    )

    group_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("groups.id", ondelete="CASCADE"))
    title: Mapped[str] = mapped_column(String(120, collation="NOCASE"))
    description: Mapped[str | None] = mapped_column(Text)
    notes: Mapped[str | None] = mapped_column(Text)
    category_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("categories.id", ondelete="SET NULL"), index=True
    )
    owner_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), index=True
    )
    """The responsible member; null = unowned."""
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), index=True
    )
    status: Mapped[ActivityStatus] = mapped_column(
        str_enum(ActivityStatus, 12), default=ActivityStatus.IDEA
    )
    due_date: Mapped[date | None]
    """"Do it by"; a floating date, not a calendar event."""
    estimated_cost: Mapped[int | None]
    """Whole currency units (an estimate)."""
    currency: Mapped[str | None] = mapped_column(String(3))
    cost_per_person: Mapped[bool] = mapped_column(default=True)
    location_name: Mapped[str | None] = mapped_column(String(120))
    address: Mapped[str | None] = mapped_column(String(300))
    """The app opens maps from this text (no coordinates)."""
    links: Mapped[list[dict[str, Any]]] = mapped_column(JSON, default=list)
    """``[{url, label}]``, at most 10."""
    attributes: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    """Custom-field values ``{key: str | number}``; never stores nulls (contract section 6)."""
    version: Mapped[int] = mapped_column(default=1)
    """Optimistic lock: bumped by every PUT and every server-side change to a written field."""
    status_changed_at: Mapped[datetime] = mapped_column(default=utcnow)
    completed_at: Mapped[datetime | None]
    """Set on entering ``done``, cleared on leaving it (the recap counts these)."""


class ActivityInterest(Base):
    """A member is interested in an activity."""

    __tablename__ = "activity_interests"

    activity_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("activities.id", ondelete="CASCADE"), primary_key=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True
    )
    created_at: Mapped[datetime] = mapped_column(default=utcnow)
