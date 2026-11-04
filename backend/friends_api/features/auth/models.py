import uuid
from datetime import datetime
from enum import StrEnum

from sqlalchemy import CheckConstraint, ForeignKey, SmallInteger, String
from sqlalchemy.orm import Mapped, mapped_column

from friends_api.core.db import Base, IdMixin, TimestampMixin, utcnow

DELETED_USER_NAME = "Deleted user"


class User(IdMixin, TimestampMixin, Base):
    __tablename__ = "users"
    __table_args__ = (
        CheckConstraint("(birthday_month IS NULL) = (birthday_day IS NULL)", name="birthday_pair"),
        CheckConstraint(
            "birthday_year IS NULL OR birthday_month IS NOT NULL", name="birthday_year"
        ),
        CheckConstraint(
            "birthday_month IS NULL OR "
            "(birthday_month BETWEEN 1 AND 12 AND birthday_day BETWEEN 1 AND 31)",
            name="birthday_range",
        ),
    )

    email: Mapped[str] = mapped_column(String(254, collation="NOCASE"), unique=True)
    """Trimmed and lowercased on input; deleted users hold 'deleted-<id>@invalid'."""
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
    last_login_at: Mapped[datetime | None]
    deleted_at: Mapped[datetime | None]
    email_verified_at: Mapped[datetime | None]
    """When the user proved they read this address (a verification or password-reset link)."""
    notify_polls: Mapped[bool] = mapped_column(default=True)
    notify_wheel: Mapped[bool] = mapped_column(default=True)
    notify_reminders: Mapped[bool] = mapped_column(default=True)
    notify_members: Mapped[bool] = mapped_column(default=True)
    notify_plans: Mapped[bool] = mapped_column(default=True)
    """Which notifications I get, by email and push (contract section 18.4)."""
    notify_email: Mapped[bool] = mapped_column(default=False)
    """Opt-in: notifications come by browser push; email (to a verified address) only when
    switched on."""
    calendar_feed_token: Mapped[str | None] = mapped_column(String(64), unique=True, index=True)
    """The secret in my webcal feed URL (contract section 5.10); null when the feed is off.
    Stored as is so the URL can be shown again: it only reads what the database holds anyway."""

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


class EmailTokenPurpose(StrEnum):
    VERIFY_EMAIL = "verify_email"
    RESET_PASSWORD = "reset_password"  # noqa: S105 - a purpose, not a secret


class EmailToken(IdMixin, Base):
    """A single-use link sent by email (contract section 18.2). Only the hash is stored."""

    __tablename__ = "email_tokens"
    __table_args__ = (
        CheckConstraint("purpose IN ('verify_email', 'reset_password')", name="purpose"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    purpose: Mapped[str] = mapped_column(String(20))
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    """sha256 hex digest of the token in the link."""
    email: Mapped[str] = mapped_column(String(254))
    """The address it was sent to: it only counts while that is still the user's address."""
    expires_at: Mapped[datetime]
    used_at: Mapped[datetime | None]
    created_at: Mapped[datetime] = mapped_column(default=utcnow)
