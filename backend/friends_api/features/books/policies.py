"""Book permissions (contract section 17.3); they also compute the ``can_*`` flags.

Any member may add a book and join or leave a queue.
"""

from friends_api.features.books.models import Book
from friends_api.features.groups.models import Membership


def can_edit_book(actor: Membership, book: Book) -> bool:
    """Edit or delete the book."""
    return actor.is_admin or actor.user_id == book.owner_id


def can_hand_over_book(actor: Membership, book: Book) -> bool:
    """Lend the book on, or mark it back with its owner."""
    holder = book.holder_id or book.owner_id
    return actor.is_admin or actor.user_id in (book.owner_id, holder)
