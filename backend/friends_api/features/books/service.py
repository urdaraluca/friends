"""A group's book archive (contract section 17).

A book is with its owner while ``holder_id`` is null. Handing it over sets the holder and takes
them out of the queue; handing it back to the owner clears the holder. Nothing checks that a
book really changed hands: the members say so.
"""

import uuid
from collections import defaultdict
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Any

from sqlalchemy import delete, func, select, update
from sqlalchemy.orm import Session

from friends_api.core.db import utcnow
from friends_api.core.errors import Conflict, Forbidden
from friends_api.features.auth.models import User
from friends_api.features.books import policies
from friends_api.features.books.models import MAX_BOOKS_PER_GROUP, Book, BookQueueEntry
from friends_api.features.books.schemas import Book as BookOut
from friends_api.features.books.schemas import BookQueueEntry as BookQueueEntryOut
from friends_api.features.books.schemas import BookWrite
from friends_api.features.group_log.service import log_event
from friends_api.features.groups import service as groups_service
from friends_api.features.groups.models import Membership
from friends_api.features.groups.service import GroupAccess, invalid_reference, limit_reached
from friends_api.features.users.lookup import public_user, users_by_id


@dataclass(frozen=True, slots=True)
class BookAccess:
    """A book and the caller's membership in its group."""

    book: Book
    membership: Membership


def get_access(db: Session, book_id: uuid.UUID, user_id: uuid.UUID) -> BookAccess | None:
    row = db.execute(
        select(Book, Membership)
        .join(Membership, Membership.group_id == Book.group_id)
        .where(Book.id == book_id, Membership.user_id == user_id)
    ).first()
    return BookAccess(book=row[0], membership=row[1]) if row else None


# --- reading ------------------------------------------------------------------------------


def build_books(db: Session, actor: Membership, books: Sequence[Book]) -> list[BookOut]:
    """Responses for books of one group, with two queries however many there are (queues,
    users)."""
    if not books:
        return []
    queues: defaultdict[uuid.UUID, list[BookQueueEntry]] = defaultdict(list)
    for entry in db.scalars(
        select(BookQueueEntry)
        .where(BookQueueEntry.book_id.in_([book.id for book in books]))
        .order_by(BookQueueEntry.joined_at, BookQueueEntry.user_id)
    ):
        queues[entry.book_id].append(entry)
    users = users_by_id(
        db,
        [
            *(book.owner_id for book in books),
            *(book.holder_id for book in books),
            *(entry.user_id for queue in queues.values() for entry in queue),
        ],
    )
    return [
        BookOut(
            id=book.id,
            group_id=book.group_id,
            title=book.title,
            author=book.author,
            description=book.description,
            owner=public_user(users, book.owner_id),
            holder=public_user(users, book.holder_id),
            held_since=book.held_since,
            queue=[
                BookQueueEntryOut(user=user, joined_at=entry.joined_at)
                for entry in queues[book.id]
                if (user := public_user(users, entry.user_id)) is not None
            ],
            in_my_queue=any(entry.user_id == actor.user_id for entry in queues[book.id]),
            can_edit=policies.can_edit_book(actor, book),
            can_hand_over=policies.can_hand_over_book(actor, book),
            created_at=book.created_at,
            updated_at=book.updated_at,
        )
        for book in books
    ]


def to_book(db: Session, access: BookAccess) -> BookOut:
    return build_books(db, access.membership, [access.book])[0]


def list_books(db: Session, access: GroupAccess) -> list[BookOut]:
    """Every book in the group, by title (case-insensitively)."""
    books = db.scalars(
        select(Book).where(Book.group_id == access.group.id).order_by(Book.title, Book.id)
    ).all()
    return build_books(db, access.membership, books)


# --- writing ------------------------------------------------------------------------------


def _log(db: Session, book: Book, actor_id: uuid.UUID | None, action: str, **data: Any) -> None:
    """A ``book.*`` row (contract section 3.2), with the title the feed shows once the book is
    gone."""
    log_event(
        db,
        group_id=book.group_id,
        actor_id=actor_id,
        action=action,
        subject_type="book",
        subject_id=book.id,
        data={"title": book.title, **data},
    )


def _ensure_can_edit(access: BookAccess) -> None:
    if not policies.can_edit_book(access.membership, access.book):
        raise Forbidden("Only the book's owner or an admin can do this.")


def create_book(db: Session, access: GroupAccess, body: BookWrite) -> Book:
    """Any member; they own the book, and it is with them. Flushes; the caller commits."""
    count = db.scalar(select(func.count()).where(Book.group_id == access.group.id)) or 0
    if count >= MAX_BOOKS_PER_GROUP:
        raise limit_reached(f"A group can have at most {MAX_BOOKS_PER_GROUP} books.")
    book = Book(
        group_id=access.group.id,
        owner_id=access.membership.user_id,
        title=body.title,
        author=body.author,
        description=body.description,
    )
    db.add(book)
    db.flush()
    _log(db, book, access.membership.user_id, "book.added")
    return book


def update_book(db: Session, access: BookAccess, body: BookWrite) -> None:
    _ensure_can_edit(access)
    book = access.book
    changed = [field for field, value in body.model_dump().items() if getattr(book, field) != value]
    if changed:
        for field in changed:
            setattr(book, field, getattr(body, field))
        _log(db, book, access.membership.user_id, "book.updated", fields=changed)
    db.commit()


def delete_book(db: Session, access: BookAccess) -> None:
    _ensure_can_edit(access)
    book = access.book
    _log(db, book, access.membership.user_id, "book.deleted")
    db.delete(book)
    db.commit()


def join_queue(db: Session, access: BookAccess) -> None:
    """Idempotent. The owner and the current holder can't queue for the book."""
    book, user_id = access.book, access.membership.user_id
    if user_id == book.owner_id:
        raise Conflict("This is your book.", code="own_book")
    if user_id == book.holder_id:
        raise Conflict("You have this book already.", code="already_holding")
    if db.get(BookQueueEntry, (book.id, user_id)) is None:
        db.add(BookQueueEntry(book_id=book.id, user_id=user_id))
        _log(db, book, user_id, "book.queue_joined")
    db.commit()


def leave_queue(db: Session, access: BookAccess) -> None:
    """Idempotent."""
    entry = db.get(BookQueueEntry, (access.book.id, access.membership.user_id))
    if entry is not None:
        db.delete(entry)
        _log(db, access.book, access.membership.user_id, "book.queue_left")
    db.commit()


def hand_over(db: Session, access: BookAccess, to_user_id: uuid.UUID | None) -> None:
    """Gives the book to ``to_user_id`` (any member, usually the first in the queue) and takes
    them out of the queue; null (or the owner) means it is back with its owner. Handing it to
    whoever has it already changes nothing."""
    book, actor = access.book, access.membership
    if not policies.can_hand_over_book(actor, book):
        raise Forbidden("Only the book's owner, whoever has it or an admin can do this.")
    if to_user_id is None or to_user_id == book.owner_id:
        if book.holder_id is not None:
            book.holder_id = None
            book.held_since = None
            _log(db, book, actor.user_id, "book.returned")
        db.commit()
        return
    if to_user_id == book.holder_id:
        db.commit()
        return
    if db.get(Membership, (book.group_id, to_user_id)) is None:
        raise invalid_reference("to_user_id", "Not a member of this group.")
    recipient = db.get(User, to_user_id)
    book.holder_id = to_user_id
    book.held_since = utcnow()
    db.execute(
        delete(BookQueueEntry).where(
            BookQueueEntry.book_id == book.id, BookQueueEntry.user_id == to_user_id
        )
    )
    _log(
        db,
        book,
        actor.user_id,
        "book.lent",
        to=str(to_user_id),
        to_name=recipient.display_name if recipient else None,
    )
    db.commit()


def _on_membership_end(db: Session, group_id: uuid.UUID, user_id: uuid.UUID) -> None:
    """Contract section 17.4: the leaver's books leave with them, the books they hold count as
    back with their owners, and they leave every queue in the group."""
    group_books = select(Book.id).where(Book.group_id == group_id)
    db.execute(
        delete(BookQueueEntry).where(
            BookQueueEntry.user_id == user_id, BookQueueEntry.book_id.in_(group_books)
        )
    )
    db.execute(
        update(Book)
        .where(Book.group_id == group_id, Book.holder_id == user_id)
        .values(holder_id=None, held_since=None, updated_at=utcnow())
    )
    db.execute(delete(Book).where(Book.group_id == group_id, Book.owner_id == user_id))


groups_service.MEMBERSHIP_END_CLEANUPS.append(_on_membership_end)
