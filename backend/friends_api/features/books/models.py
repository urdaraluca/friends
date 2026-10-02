"""A group's book archive (contract section 17): the books members own and lend each other,
and who is waiting for each."""

import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column

from friends_api.core.db import Base, IdMixin, TimestampMixin, utcnow

MAX_BOOKS_PER_GROUP = 1000


class Book(IdMixin, TimestampMixin, Base):
    __tablename__ = "books"
    __table_args__ = (Index("ix_books_group_title", "group_id", "title"),)

    group_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("groups.id", ondelete="CASCADE"))
    owner_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    """Who added it. The book leaves the group with them."""
    title: Mapped[str] = mapped_column(String(200, collation="NOCASE"))
    author: Mapped[str | None] = mapped_column(String(120))
    description: Mapped[str | None] = mapped_column(String(5000))
    holder_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), index=True
    )
    """Who has it now; null while it is with its owner."""
    held_since: Mapped[datetime | None]
    """When ``holder_id`` got it; null with the owner."""


class BookQueueEntry(Base):
    """A member waiting to borrow a book. The queue is ordered by ``joined_at``."""

    __tablename__ = "book_queue"

    book_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("books.id", ondelete="CASCADE"), primary_key=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True
    )
    joined_at: Mapped[datetime] = mapped_column(default=utcnow)
