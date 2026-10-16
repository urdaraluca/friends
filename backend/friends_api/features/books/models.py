"""A group's book archive (contract section 17): the books members own and lend each other,
who is waiting for each, their covers and the group's ratings."""

import uuid
from datetime import datetime
from enum import StrEnum

from sqlalchemy import CheckConstraint, ForeignKey, Index, LargeBinary, SmallInteger, String
from sqlalchemy.orm import Mapped, mapped_column

from friends_api.core.db import Base, IdMixin, TimestampMixin, str_enum, utcnow

MAX_BOOKS_PER_GROUP = 1000
MAX_COVER_BYTES = 2 * 1024 * 1024


class BookGenre(StrEnum):
    """A book's genre (contract section 17.2). The app translates the names."""

    FICTION = "fiction"
    FANTASY = "fantasy"
    SCI_FI = "sci_fi"
    MYSTERY_THRILLER = "mystery_thriller"
    ROMANCE = "romance"
    HORROR = "horror"
    CLASSICS = "classics"
    HISTORY = "history"
    BIOGRAPHY = "biography"
    NON_FICTION = "non_fiction"
    SELF_HELP = "self_help"
    POETRY = "poetry"
    CHILDREN = "children"
    YOUNG_ADULT = "young_adult"
    COMICS = "comics"
    OTHER = "other"


class Book(IdMixin, TimestampMixin, Base):
    __tablename__ = "books"
    __table_args__ = (Index("ix_books_group_title", "group_id", "title"),)

    group_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("groups.id", ondelete="CASCADE"))
    owner_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    """Whose book it is. The book leaves the group with them."""
    added_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )
    """Who put it on the shelf (maybe for its owner); they may edit it too."""
    title: Mapped[str] = mapped_column(String(200, collation="NOCASE"))
    author: Mapped[str | None] = mapped_column(String(120))
    description: Mapped[str | None] = mapped_column(String(5000))
    isbn: Mapped[str | None] = mapped_column(String(13))
    """ISBN-13, digits only."""
    genre: Mapped[BookGenre | None] = mapped_column(str_enum(BookGenre, 20))
    language: Mapped[str | None] = mapped_column(String(2))
    """ISO 639-1, lowercase."""
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


class BookCover(Base):
    """A book's cover picture: a photo a member took, or the one its ISBN lookup found."""

    __tablename__ = "book_covers"

    book_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("books.id", ondelete="CASCADE"), primary_key=True
    )
    content_type: Mapped[str] = mapped_column(String(20))
    data: Mapped[bytes] = mapped_column(LargeBinary)
    updated_at: Mapped[datetime] = mapped_column(default=utcnow, onupdate=utcnow)


class BookRating(Base):
    """A member's stars for a book, 1 to 5."""

    __tablename__ = "book_ratings"
    __table_args__ = (CheckConstraint("stars BETWEEN 1 AND 5", name="stars_range"),)

    book_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("books.id", ondelete="CASCADE"), primary_key=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True
    )
    stars: Mapped[int] = mapped_column(SmallInteger)
    rated_at: Mapped[datetime] = mapped_column(default=utcnow, onupdate=utcnow)
