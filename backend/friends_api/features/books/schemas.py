"""Book schemas (contract sections 9 and 17)."""

import uuid
from datetime import datetime
from typing import Annotated

from pydantic import BaseModel, StringConstraints

from friends_api.core.schemas import RequestModel
from friends_api.features.users.schemas import UserPublic

BookTitle = Annotated[str, StringConstraints(min_length=1, max_length=200)]
BookAuthor = Annotated[str, StringConstraints(max_length=120)]
BookDescription = Annotated[str, StringConstraints(max_length=5000)]


class BookWrite(RequestModel):
    """A new book (the caller owns it), or the complete new state of one."""

    title: BookTitle
    author: BookAuthor | None = None
    description: BookDescription | None = None


class Handover(RequestModel):
    to_user_id: uuid.UUID | None = None
    """The member who gets the book next; null gives it back to its owner."""


class BookQueueEntry(BaseModel):
    user: UserPublic
    joined_at: datetime


class Book(BaseModel):
    id: uuid.UUID
    group_id: uuid.UUID
    title: str
    author: str | None
    description: str | None
    owner: UserPublic | None
    """Null only for a moment while the owner's account is being deleted."""
    holder: UserPublic | None
    """Who has it now; null while it is with its owner."""
    held_since: datetime | None
    queue: list[BookQueueEntry]
    """Who is waiting for it, first come first served."""
    in_my_queue: bool
    can_edit: bool
    """Edit and delete: the owner or an admin+."""
    can_hand_over: bool
    """The owner, the current holder or an admin+."""
    created_at: datetime
    updated_at: datetime
