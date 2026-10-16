from typing import Annotated

from fastapi import APIRouter, Depends, File, Header, Response, UploadFile, status

from friends_api.core.errors import NotFound, Unprocessable
from friends_api.core.ratelimit import limit_by_ip
from friends_api.deps import CurrentUser, DbSession, GroupMember
from friends_api.features.books import service
from friends_api.features.books.deps import BookMember, IsbnLookupClient
from friends_api.features.books.isbn import normalize_isbn
from friends_api.features.books.models import MAX_COVER_BYTES
from friends_api.features.books.schemas import (
    Book,
    BookCreate,
    BookWrite,
    Handover,
    IsbnLookup,
    RatingWrite,
)
from friends_api.features.books.service import BookAccess

router = APIRouter(tags=["books"])

_COVER_TYPES = ("image/jpeg", "image/png", "image/webp")


@router.get("/groups/{group_id}/books")
def list_books(db: DbSession, access: GroupMember) -> list[Book]:
    """Every book in the group, by title."""
    return service.list_books(db, access)


@router.post("/groups/{group_id}/books", status_code=status.HTTP_201_CREATED)
def create_book(body: BookCreate, db: DbSession, access: GroupMember) -> Book:
    """Any member. The book is theirs and with them, unless the body names other members."""
    book = service.create_book(db, access, body)
    db.commit()
    return service.to_book(db, BookAccess(book=book, membership=access.membership))


@router.get(
    "/books/isbn/{isbn}",
    dependencies=[Depends(limit_by_ip("isbn_lookup"))],
)
def look_up_isbn(isbn: str, lookup: IsbnLookupClient, _user: CurrentUser) -> IsbnLookup:
    """What the book catalogues know about an ISBN-10 or ISBN-13."""
    normalized = normalize_isbn(isbn)
    if normalized is None:
        raise Unprocessable("Not a valid ISBN-10 or ISBN-13.", code="invalid_isbn")
    found = lookup.look_up(normalized)
    if found is None:
        raise NotFound("No book found for this ISBN.")
    return IsbnLookup(
        isbn=found.isbn,
        title=found.title,
        author=found.author,
        description=found.description,
        genre=found.genre,
        language=found.language,
        cover_url=found.cover_url,
    )


@router.get("/books/{book_id}")
def get_book(db: DbSession, access: BookMember) -> Book:
    return service.to_book(db, access)


@router.put("/books/{book_id}")
def update_book(body: BookWrite, db: DbSession, access: BookMember) -> Book:
    """The owner, whoever added it or an admin."""
    service.update_book(db, access, body)
    return service.to_book(db, access)


@router.delete("/books/{book_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_book(db: DbSession, access: BookMember) -> None:
    """The owner, whoever added it or an admin."""
    service.delete_book(db, access)


@router.put("/books/{book_id}/queue")
def join_book_queue(db: DbSession, access: BookMember) -> Book:
    """Joins the end of the queue (idempotent). Not for the owner or whoever has the book."""
    service.join_queue(db, access)
    return service.to_book(db, access)


@router.delete("/books/{book_id}/queue")
def leave_book_queue(db: DbSession, access: BookMember) -> Book:
    """Leaves the queue (idempotent)."""
    service.leave_queue(db, access)
    return service.to_book(db, access)


@router.post("/books/{book_id}/handover")
def hand_over_book(body: Handover, db: DbSession, access: BookMember) -> Book:
    """The owner, whoever has the book or an admin.

    Gives it to a member, who leaves the queue.
    A null ``to_user_id`` gives it back to its owner."""
    service.hand_over(db, access, body.to_user_id)
    return service.to_book(db, access)


# --- covers -------------------------------------------------------------------------------


@router.get(
    "/books/{book_id}/cover",
    response_class=Response,
    responses={
        200: {
            "content": {
                kind: {"schema": {"type": "string", "format": "binary"}} for kind in _COVER_TYPES
            },
            "description": "The cover image.",
        },
        304: {"description": "The cover hasn't changed (If-None-Match)."},
    },
)
def get_book_cover(
    db: DbSession,
    access: BookMember,
    if_none_match: Annotated[str | None, Header(include_in_schema=False)] = None,
) -> Response:
    """The book's cover image."""
    cover = service.get_cover(db, access)
    etag = f'"{int(cover.updated_at.timestamp() * 1000)}"'
    headers = {"ETag": etag, "Cache-Control": "private, no-cache"}
    if if_none_match == etag:
        return Response(status_code=status.HTTP_304_NOT_MODIFIED, headers=headers)
    return Response(cover.data, media_type=cover.content_type, headers=headers)


@router.put("/books/{book_id}/cover")
def upload_book_cover(
    file: Annotated[UploadFile, File(description="A JPEG, PNG or WebP image, up to 2 MB.")],
    db: DbSession,
    access: BookMember,
) -> Book:
    """The owner, whoever added it or an admin. Replaces the cover."""
    service.set_cover(db, access, file.file.read(MAX_COVER_BYTES + 1))
    return service.to_book(db, access)


@router.post("/books/{book_id}/cover/isbn")
def use_isbn_cover(db: DbSession, access: BookMember, lookup: IsbnLookupClient) -> Book:
    """The owner, whoever added it or an admin. The cover the book catalogues have for its ISBN."""
    service.use_isbn_cover(db, access, lookup)
    return service.to_book(db, access)


@router.delete("/books/{book_id}/cover")
def delete_book_cover(db: DbSession, access: BookMember) -> Book:
    """The owner, whoever added it or an admin. Removes the cover (idempotent)."""
    service.delete_cover(db, access)
    return service.to_book(db, access)


# --- ratings ------------------------------------------------------------------------------


@router.put("/books/{book_id}/rating")
def rate_book(body: RatingWrite, db: DbSession, access: BookMember) -> Book:
    """Any member. Sets the caller's stars, 1 to 5."""
    service.rate(db, access, body.stars)
    return service.to_book(db, access)


@router.delete("/books/{book_id}/rating")
def unrate_book(db: DbSession, access: BookMember) -> Book:
    """Any member. Removes the caller's stars (idempotent)."""
    service.unrate(db, access)
    return service.to_book(db, access)
