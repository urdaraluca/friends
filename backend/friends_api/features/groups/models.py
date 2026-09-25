import uuid
from datetime import datetime
from enum import StrEnum

from sqlalchemy import ForeignKey, Index, String, text
from sqlalchemy.orm import Mapped, mapped_column

from friends_api.core.db import Base, IdMixin, TimestampMixin, str_enum, utcnow


class Role(StrEnum):
    OWNER = "owner"
    ADMIN = "admin"
    MEMBER = "member"


class Group(IdMixin, TimestampMixin, Base):
    __tablename__ = "groups"

    name: Mapped[str] = mapped_column(String(60))
    description: Mapped[str | None] = mapped_column(String(500))
    emoji: Mapped[str | None] = mapped_column(String(16))
    color: Mapped[str | None] = mapped_column(String(7))
    """'#RRGGBB', stored uppercase."""
    currency: Mapped[str] = mapped_column(String(3), default="EUR")
    """Default currency for activity costs (ISO 4217 shape)."""
    timezone: Mapped[str] = mapped_column(String(64))
    """Default for events; month/year boundaries for the recap."""
    members_can_invite: Mapped[bool] = mapped_column(default=True)
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), index=True
    )


class Membership(Base):
    __tablename__ = "memberships"
    __table_args__ = (
        # At most one owner per group; the service guarantees at least one.
        Index(
            "uq_memberships_owner",
            "group_id",
            unique=True,
            sqlite_where=text("role = 'owner'"),
        ),
    )

    group_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("groups.id", ondelete="CASCADE"), primary_key=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True
    )
    role: Mapped[Role] = mapped_column(str_enum(Role, 10))
    show_birthday: Mapped[bool] = mapped_column(default=True)
    invite_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("invites.id", ondelete="SET NULL"), index=True
    )
    """The invite used to join; null for the creator."""
    joined_at: Mapped[datetime] = mapped_column(default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(default=utcnow, onupdate=utcnow)

    @property
    def is_owner(self) -> bool:
        return self.role is Role.OWNER

    @property
    def is_admin(self) -> bool:
        """Admin or owner ("admin+")."""
        return self.role in (Role.OWNER, Role.ADMIN)
