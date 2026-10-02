"""Loader for flat ``/books/{book_id}`` routes (contract section 7.1)."""

import uuid
from typing import Annotated

from fastapi import Depends

from friends_api.core.errors import NotFound
from friends_api.deps import CurrentUser, DbSession
from friends_api.features.books import service
from friends_api.features.books.service import BookAccess


def load_book(book_id: uuid.UUID, db: DbSession, user: CurrentUser) -> BookAccess:
    """The book plus the caller's membership in its group. A missing book and a non-member
    caller get the same 404."""
    access = service.get_access(db, book_id, user.id)
    if access is None:
        raise NotFound("No such book.")
    return access


BookMember = Annotated[BookAccess, Depends(load_book)]
