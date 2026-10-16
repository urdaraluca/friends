"""Book schemas (contract sections 9 and 17)."""

import uuid
from datetime import datetime
from typing import Annotated

from pydantic import AfterValidator, BaseModel, Field, StringConstraints

from friends_api.core.schemas import RequestModel
from friends_api.features.books.isbn import normalize_isbn
from friends_api.features.books.models import BookGenre
from friends_api.features.users.schemas import UserPublic

BookTitle = Annotated[str, StringConstraints(min_length=1, max_length=200)]
BookAuthor = Annotated[str, StringConstraints(max_length=120)]
BookDescription = Annotated[str, StringConstraints(max_length=5000)]
LanguageCode = Annotated[
    str, StringConstraints(to_lower=True, pattern=r"^[a-zA-Z]{2}$", min_length=2, max_length=2)
]


def _isbn(value: str) -> str:
    isbn = normalize_isbn(value)
    if isbn is None:
        raise ValueError("Not a valid ISBN-10 or ISBN-13.")
    return isbn


Isbn = Annotated[str, StringConstraints(max_length=20), AfterValidator(_isbn)]
"""An ISBN-10 or ISBN-13 (spaces and hyphens allowed), stored as its ISBN-13."""


class BookWrite(RequestModel):
    """A new book, or the complete new state of one."""

    title: BookTitle
    author: BookAuthor | None = None
    description: BookDescription | None = None
    isbn: Isbn | None = None
    genre: BookGenre | None = None
    language: LanguageCode | None = None
    """ISO 639-1, e.g. "ro"."""
    owner_id: uuid.UUID | None = None
    """A member whose book it is. Null: the caller on create; unchanged on update."""


class BookCreate(BookWrite):
    holder_id: uuid.UUID | None = None
    """The member who has it now. Null (or the owner): it is with its owner."""


class Handover(RequestModel):
    to_user_id: uuid.UUID | None = None
    """The member who gets the book next; null gives it back to its owner."""


class RatingWrite(RequestModel):
    stars: Annotated[int, Field(ge=1, le=5)]


class BookQueueEntry(BaseModel):
    user: UserPublic
    joined_at: datetime


class Book(BaseModel):
    id: uuid.UUID
    group_id: uuid.UUID
    title: str
    author: str | None
    description: str | None
    isbn: str | None
    """ISBN-13."""
    genre: BookGenre | None
    language: str | None
    """ISO 639-1."""
    cover_updated_at: datetime | None
    """When the cover last changed (it is at ``GET /books/{id}/cover``); null without one."""
    owner: UserPublic | None
    """Null only for a moment while the owner's account is being deleted."""
    holder: UserPublic | None
    """Who has it now; null while it is with its owner."""
    held_since: datetime | None
    queue: list[BookQueueEntry]
    """Who is waiting for it, first come first served."""
    in_my_queue: bool
    rating_average: float | None
    """The group's average stars, rounded to one decimal; null with no ratings."""
    rating_count: int
    my_rating: int | None
    """The caller's stars, 1 to 5; null if they haven't rated it."""
    can_edit: bool
    """Edit and delete, the cover too: the owner, whoever added it, or an admin+."""
    can_hand_over: bool
    """The owner, the current holder or an admin+."""
    created_at: datetime
    updated_at: datetime


class IsbnLookup(BaseModel):
    """What the book catalogues know about an ISBN; the app fills its form with it."""

    isbn: str
    """ISBN-13."""
    title: str
    author: str | None
    description: str | None
    genre: BookGenre | None
    language: str | None
    cover_url: str | None
    """An https image to preview; save it with ``POST /books/{id}/cover/isbn``."""
