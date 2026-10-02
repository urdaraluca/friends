"""The demo group's book archive (contract section 17): each member's shelf, a few books out on
loan and a queue or two."""

from datetime import timedelta

from sqlalchemy.orm import Session

from friends_api.demo.context import DemoContext
from friends_api.features.books import service as books_service
from friends_api.features.books.models import BookQueueEntry
from friends_api.features.books.schemas import BookWrite

# Per demo user (Ana, Bogdan, Carla): (title, author, description).
SHELVES: tuple[list[tuple[str, str, str | None]], ...] = (
    [
        ("The Name of the Rose", "Umberto Eco", "A murder mystery in a medieval abbey."),
        ("Dune", "Frank Herbert", None),
        ("Middlemarch", "George Eliot", "Slow, and worth it."),
    ],
    [
        ("The Hitchhiker's Guide to the Galaxy", "Douglas Adams", "Bring a towel."),
        ("Maitreyi", "Mircea Eliade", None),
        ("Sapiens", "Yuval Noah Harari", None),
    ],
    [
        ("Normal People", "Sally Rooney", None),
        ("The Hobbit", "J. R. R. Tolkien", "The illustrated edition."),
    ],
)


def create_books(db: Session, ctx: DemoContext) -> None:
    ana, bogdan, carla = ctx.users
    books = {}
    for user, shelf in zip(ctx.users, SHELVES, strict=True):
        for title, author, description in shelf:
            body = BookWrite(title=title, author=author, description=description)
            books[title] = books_service.create_book(db, ctx.access(user), body)

    # Out on loan: Bogdan has Ana's Dune, and Carla has his Hitchhiker's Guide.
    for title, holder, days in (
        ("Dune", bogdan, 12),
        ("The Hitchhiker's Guide to the Galaxy", carla, 3),
    ):
        book = books[title]
        book.holder_id = holder.id
        book.held_since = ctx.now - timedelta(days=days)

    # Carla is next for Dune, then Ana wants Sapiens and Bogdan The Hobbit.
    for title, user in (("Dune", carla), ("Sapiens", ana), ("The Hobbit", bogdan)):
        db.add(BookQueueEntry(book_id=books[title].id, user_id=user.id))
