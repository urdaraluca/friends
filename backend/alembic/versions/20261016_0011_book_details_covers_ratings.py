"""book details, covers and ratings

Revision ID: 0011
Revises: 0010
Create Date: 2026-10-16 12:00:00.000000

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

from friends_api.core.db import UTCDateTime

# revision identifiers, used by Alembic.
revision: str = "0011"
down_revision: str | Sequence[str] | None = "0010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_GENRES = (
    "fiction",
    "fantasy",
    "sci_fi",
    "mystery_thriller",
    "romance",
    "horror",
    "classics",
    "history",
    "biography",
    "non_fiction",
    "self_help",
    "poetry",
    "children",
    "young_adult",
    "comics",
    "other",
)


# Adding a foreign key rebuilds the table on SQLite, and reflection loses the title's NOCASE.
_BOOKS_REFLECT_ARGS = [
    sa.Column("title", sa.String(length=200, collation="NOCASE"), nullable=False)
]


def upgrade() -> None:
    with op.batch_alter_table(
        "books", schema=None, reflect_args=_BOOKS_REFLECT_ARGS
    ) as batch_op:
        batch_op.add_column(sa.Column("isbn", sa.String(length=13), nullable=True))
        batch_op.add_column(
            sa.Column(
                "genre",
                sa.Enum(
                    *_GENRES,
                    name="bookgenre",
                    native_enum=False,
                    create_constraint=False,
                    length=20,
                ),
                nullable=True,
            )
        )
        batch_op.add_column(sa.Column("language", sa.String(length=2), nullable=True))
        batch_op.add_column(sa.Column("added_by_id", sa.Uuid(), nullable=True))
        batch_op.create_foreign_key(
            batch_op.f("fk_books_added_by_id_users"),
            "users",
            ["added_by_id"],
            ["id"],
            ondelete="SET NULL",
        )
    # Until now, every book was added by its owner.
    op.execute("UPDATE books SET added_by_id = owner_id")

    op.create_table(
        "book_covers",
        sa.Column("book_id", sa.Uuid(), nullable=False),
        sa.Column("content_type", sa.String(length=20), nullable=False),
        sa.Column("data", sa.LargeBinary(), nullable=False),
        sa.Column("updated_at", UTCDateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["book_id"],
            ["books.id"],
            name=op.f("fk_book_covers_book_id_books"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("book_id", name=op.f("pk_book_covers")),
    )

    op.create_table(
        "book_ratings",
        sa.Column("book_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("stars", sa.SmallInteger(), nullable=False),
        sa.Column("rated_at", UTCDateTime(), nullable=False),
        sa.CheckConstraint("stars BETWEEN 1 AND 5", name=op.f("ck_book_ratings_stars_range")),
        sa.ForeignKeyConstraint(
            ["book_id"],
            ["books.id"],
            name=op.f("fk_book_ratings_book_id_books"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_book_ratings_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("book_id", "user_id", name=op.f("pk_book_ratings")),
    )
    with op.batch_alter_table("book_ratings", schema=None) as batch_op:
        batch_op.create_index(batch_op.f("ix_book_ratings_user_id"), ["user_id"], unique=False)


def downgrade() -> None:
    with op.batch_alter_table("book_ratings", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_book_ratings_user_id"))
    op.drop_table("book_ratings")
    op.drop_table("book_covers")
    with op.batch_alter_table(
        "books", schema=None, reflect_args=_BOOKS_REFLECT_ARGS
    ) as batch_op:
        batch_op.drop_constraint(batch_op.f("fk_books_added_by_id_users"), type_="foreignkey")
        batch_op.drop_column("added_by_id")
        batch_op.drop_column("language")
        batch_op.drop_column("genre")
        batch_op.drop_column("isbn")
