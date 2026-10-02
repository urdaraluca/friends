from fastapi import APIRouter, status

from friends_api.deps import DbSession, GroupMember
from friends_api.features.books import service
from friends_api.features.books.deps import BookMember
from friends_api.features.books.schemas import Book, BookWrite, Handover
from friends_api.features.books.service import BookAccess

router = APIRouter(tags=["books"])


@router.get("/groups/{group_id}/books")
def list_books(db: DbSession, access: GroupMember) -> list[Book]:
    """Every book in the group, by title."""
    return service.list_books(db, access)


@router.post("/groups/{group_id}/books", status_code=status.HTTP_201_CREATED)
def create_book(body: BookWrite, db: DbSession, access: GroupMember) -> Book:
    """Any member. The caller owns the book, and it is with them."""
    book = service.create_book(db, access, body)
    db.commit()
    return service.to_book(db, BookAccess(book=book, membership=access.membership))


@router.get("/books/{book_id}")
def get_book(db: DbSession, access: BookMember) -> Book:
    return service.to_book(db, access)


@router.put("/books/{book_id}")
def update_book(body: BookWrite, db: DbSession, access: BookMember) -> Book:
    """The owner or an admin."""
    service.update_book(db, access, body)
    return service.to_book(db, access)


@router.delete("/books/{book_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_book(db: DbSession, access: BookMember) -> None:
    """The owner or an admin."""
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
