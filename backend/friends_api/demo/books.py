"""The demo group's book archive (contract section 17): each member's shelf, a few books out on
loan and a queue or two."""

from datetime import timedelta

from sqlalchemy.orm import Session

from friends_api.demo.context import DemoContext
from friends_api.features.books import service as books_service
from friends_api.features.books.models import BookGenre, BookQueueEntry, BookRating
from friends_api.features.books.schemas import BookCreate

G = BookGenre
# Per demo user (Ana, Bogdan, Carla): (title, author, description, ISBN, genre, language).
type Shelf = list[tuple[str, str, str | None, str | None, BookGenre, str]]
SHELVES: tuple[Shelf, ...] = (
    [
        (
            "The Name of the Rose",
            "Umberto Eco",
            "A murder mystery in a medieval abbey.",
            "9780156001311",
            G.MYSTERY_THRILLER,
            "en",
        ),
        ("Dune", "Frank Herbert", None, "9780441172719", G.SCI_FI, "en"),
        ("Middlemarch", "George Eliot", "Slow, and worth it.", "9780141439549", G.CLASSICS, "en"),
    ],
    [
        (
            "The Hitchhiker's Guide to the Galaxy",
            "Douglas Adams",
            "Bring a towel.",
            "9780330508537",
            G.SCI_FI,
            "en",
        ),
        ("Maitreyi", "Mircea Eliade", None, None, G.CLASSICS, "ro"),
        ("Sapiens", "Yuval Noah Harari", None, "9780099590088", G.HISTORY, "en"),
    ],
    [
        ("Normal People", "Sally Rooney", None, "9780571334650", G.FICTION, "en"),
        (
            "The Hobbit",
            "J. R. R. Tolkien",
            "The illustrated edition.",
            "9780261102217",
            G.FANTASY,
            "en",
        ),
    ],
)

# Who rated what: (title, [(user index, stars)]).
RATINGS: tuple[tuple[str, list[tuple[int, int]]], ...] = (
    ("Dune", [(0, 5), (1, 4)]),
    ("The Hobbit", [(0, 5), (1, 5), (2, 4)]),
    ("Middlemarch", [(0, 4)]),
    ("Maitreyi", [(1, 4), (2, 3)]),
    ("Normal People", [(2, 3)]),
)


def create_books(db: Session, ctx: DemoContext) -> None:
    ana, bogdan, carla = ctx.users
    books = {}
    for user, shelf in zip(ctx.users, SHELVES, strict=True):
        for title, author, description, isbn, genre, language in shelf:
            body = BookCreate(
                title=title,
                author=author,
                description=description,
                isbn=isbn,
                genre=genre,
                language=language,
            )
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

    for title, raters in RATINGS:
        for index, stars in raters:
            db.add(BookRating(book_id=books[title].id, user_id=ctx.users[index].id, stars=stars))
