import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import JSON, ForeignKey, Index
from sqlalchemy.orm import Mapped, mapped_column

from friends_api.core.db import Base, IdMixin, utcnow


class WheelSpin(IdMixin, Base):
    """One spin of a group's "What should we do?" wheel (contract sections 3.1 and 10).

    The server picks the result. The candidates are a snapshot, so the history survives later
    edits and deletions of the activities. There is no ``updated_at``: the only change a spin
    ever gets is its acceptance, which carries its own timestamp and is written once.
    """

    __tablename__ = "wheel_spins"
    __table_args__ = (Index("ix_wheel_spins_group_created", "group_id", "created_at"),)

    group_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("groups.id", ondelete="CASCADE"))
    spun_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), index=True
    )
    filters: Mapped[dict[str, Any]] = mapped_column(JSON)
    """``WheelFilters`` as sent, after normalization (stored for display only)."""
    candidates: Mapped[list[dict[str, Any]]] = mapped_column(JSON)
    """Snapshot ``[{id, title, category_id, color}]`` in slice order, 2..50 entries; ``color``
    is the category's effective color at spin time."""
    result_index: Mapped[int]
    """Index into ``candidates``."""
    result_activity_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("activities.id", ondelete="SET NULL"), index=True
    )
    """``candidates[result_index].id`` while that activity exists; null once it is deleted."""
    accepted_at: Mapped[datetime | None]
    accepted_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), index=True
    )
    created_at: Mapped[datetime] = mapped_column(default=utcnow)
