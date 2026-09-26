import uuid
from typing import Any

from sqlalchemy import JSON, ForeignKey, Index, String, text
from sqlalchemy.orm import Mapped, mapped_column

from friends_api.core.db import Base, IdMixin, TimestampMixin


class Category(IdMixin, TimestampMixin, Base):
    """A group's category or subcategory (at most two levels deep, contract section 6)."""

    __tablename__ = "categories"
    __table_args__ = (
        # The NOCASE collation of `name` makes both unique indexes case-insensitive.
        Index(
            "uq_categories_top_name",
            "group_id",
            "name",
            unique=True,
            sqlite_where=text("parent_id IS NULL"),
        ),
        Index(
            "uq_categories_sub_name",
            "parent_id",
            "name",
            unique=True,
            sqlite_where=text("parent_id IS NOT NULL"),
        ),
        Index("ix_categories_group_parent_position", "group_id", "parent_id", "position"),
    )

    group_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("groups.id", ondelete="CASCADE"))
    parent_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("categories.id", ondelete="CASCADE")
    )
    """The service keeps the parent top-level (depth <= 2)."""
    name: Mapped[str] = mapped_column(String(40, collation="NOCASE"))
    color: Mapped[str | None] = mapped_column(String(7))
    """'#RRGGBB'. Required for a top-level category; null on a subcategory means inherit."""
    icon: Mapped[str | None] = mapped_column(String(40))
    """An icon key (contract section 6.5) or an emoji."""
    position: Mapped[int] = mapped_column(default=0)
    field_defs: Mapped[list[dict[str, Any]]] = mapped_column(JSON, default=list)
    """Own ``FieldDef`` list, validated by the service before writing."""
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), index=True
    )
