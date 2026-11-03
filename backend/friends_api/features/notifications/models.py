import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, Index, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from friends_api.core.db import Base, IdMixin, utcnow


class NotificationDelivery(IdMixin, Base):
    """One notification email sent to one user (contract section 18.4): recorded before sending,
    so the job never sends it twice (at most once). Pruned after 60 days."""

    __tablename__ = "notification_deliveries"
    __table_args__ = (
        UniqueConstraint("user_id", "kind", "ref", name="uq_notification_deliveries_user_kind_ref"),
        Index("ix_notification_deliveries_created_at", "created_at"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    kind: Mapped[str] = mapped_column(String(20))
    """``polls``, ``wheel`` or ``reminders``."""
    ref: Mapped[str] = mapped_column(String(100))
    """What it was about: a ``group_log`` id, or ``<event or user id>:<occurrence key>``."""
    created_at: Mapped[datetime] = mapped_column(default=utcnow)
