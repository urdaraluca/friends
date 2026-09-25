import uuid
from datetime import datetime
from enum import StrEnum

from sqlalchemy import CheckConstraint, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from friends_api.core.db import Base, IdMixin, TimestampMixin


class InviteStatus(StrEnum):
    VALID = "valid"
    EXPIRED = "expired"
    REVOKED = "revoked"
    EXHAUSTED = "exhausted"


class Invite(IdMixin, TimestampMixin, Base):
    __tablename__ = "invites"
    __table_args__ = (
        CheckConstraint("use_count >= 0", name="use_count_nonneg"),
        CheckConstraint("max_uses IS NULL OR max_uses BETWEEN 1 AND 100", name="max_uses_range"),
        CheckConstraint("max_uses IS NULL OR use_count <= max_uses", name="uses_within_max"),
    )

    group_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("groups.id", ondelete="CASCADE"), index=True
    )
    code: Mapped[str] = mapped_column(String(16), unique=True)
    """10 characters of Crockford base32."""
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), index=True
    )
    expires_at: Mapped[datetime | None]
    """Null = never expires (admin+ only)."""
    max_uses: Mapped[int | None]
    """Null = unlimited."""
    use_count: Mapped[int] = mapped_column(default=0)
    revoked_at: Mapped[datetime | None]

    def status(self, now: datetime) -> InviteStatus:
        if self.revoked_at is not None:
            return InviteStatus.REVOKED
        if self.expires_at is not None and self.expires_at <= now:
            return InviteStatus.EXPIRED
        if self.max_uses is not None and self.use_count >= self.max_uses:
            return InviteStatus.EXHAUSTED
        return InviteStatus.VALID
