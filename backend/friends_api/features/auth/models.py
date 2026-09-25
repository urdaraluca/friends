import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, SmallInteger, String
from sqlalchemy.orm import Mapped, mapped_column

from friends_api.core.db import Base, IdMixin, TimestampMixin, utcnow


class User(IdMixin, TimestampMixin, Base):
    __tablename__ = "users"

    email: Mapped[str] = mapped_column(String(254), unique=True)
    """Trimmed and lowercased on input."""
    password_hash: Mapped[str | None] = mapped_column(String(255))
    """argon2id PHC string; null once the account is deleted."""
    display_name: Mapped[str] = mapped_column(String(50))
    avatar_url: Mapped[str | None] = mapped_column(String(2048))
    birthday_month: Mapped[int | None] = mapped_column(SmallInteger)
    birthday_day: Mapped[int | None] = mapped_column(SmallInteger)
    birthday_year: Mapped[int | None] = mapped_column(SmallInteger)
    timezone: Mapped[str] = mapped_column(String(64), default="UTC")
    locale: Mapped[str | None] = mapped_column(String(16))
    token_version: Mapped[int] = mapped_column(default=0)
    """Bumped to revoke every access token at once (log out everywhere)."""
    email_verified_at: Mapped[datetime | None]
    last_login_at: Mapped[datetime | None]
    deleted_at: Mapped[datetime | None]

    @property
    def is_active(self) -> bool:
        return self.deleted_at is None


class RefreshToken(IdMixin, Base):
    """One row per issued refresh token; a family is one login session, rotated on every use."""

    __tablename__ = "refresh_tokens"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    family_id: Mapped[uuid.UUID] = mapped_column(index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    """sha256 hex digest; the token itself is never stored."""
    session_started_at: Mapped[datetime]
    expires_at: Mapped[datetime]
    used_at: Mapped[datetime | None]
    revoked_at: Mapped[datetime | None]
    replaced_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("refresh_tokens.id", ondelete="SET NULL")
    )
    device_label: Mapped[str | None] = mapped_column(String(100))
    created_at: Mapped[datetime] = mapped_column(default=utcnow)
