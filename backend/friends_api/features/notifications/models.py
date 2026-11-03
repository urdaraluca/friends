import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, Index, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from friends_api.core.db import Base, IdMixin, utcnow


class NotificationDelivery(IdMixin, Base):
    """One notification sent to one user on one channel (contract section 18.4): recorded
    before sending, so the job never sends it twice (at most once). Pruned after 60 days."""

    __tablename__ = "notification_deliveries"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "channel", "kind", "ref", name="uq_notification_deliveries_unique"
        ),
        Index("ix_notification_deliveries_created_at", "created_at"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    channel: Mapped[str] = mapped_column(String(10))
    """``email`` or ``push``."""
    kind: Mapped[str] = mapped_column(String(20))
    """``polls``, ``wheel``, ``reminders``, ``members`` or ``plans``."""
    ref: Mapped[str] = mapped_column(String(100))
    """What it was about: a ``group_log`` id, ``<poll id>:closing``, or
    ``<event or user id>:<occurrence key>`` (``:1h`` for the hour-before reminder)."""
    created_at: Mapped[datetime] = mapped_column(default=utcnow)


class PushSubscription(IdMixin, Base):
    """A browser's Web Push subscription (contract section 18.6)."""

    __tablename__ = "push_subscriptions"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    endpoint: Mapped[str] = mapped_column(String(1000), unique=True)
    p256dh: Mapped[str] = mapped_column(String(200))
    auth: Mapped[str] = mapped_column(String(100))
    created_at: Mapped[datetime] = mapped_column(default=utcnow)
    last_used_at: Mapped[datetime | None]
