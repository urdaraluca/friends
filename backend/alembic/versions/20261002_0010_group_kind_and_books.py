"""group kind and books

Revision ID: 0010
Revises: 0009
Create Date: 2026-10-02 12:00:00.000000

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

from friends_api.core.db import UTCDateTime

# revision identifiers, used by Alembic.
revision: str = "0010"
down_revision: str | Sequence[str] | None = "0009"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("groups", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column(
                "kind",
                sa.Enum(
                    "general",
                    "movie_night",
                    "book_club",
                    name="groupkind",
                    native_enum=False,
                    length=12,
                ),
                server_default="general",
                nullable=False,
            )
        )

    op.create_table(
        "books",
        sa.Column("group_id", sa.Uuid(), nullable=False),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("title", sa.String(length=200, collation="NOCASE"), nullable=False),
        sa.Column("author", sa.String(length=120), nullable=True),
        sa.Column("description", sa.String(length=5000), nullable=True),
        sa.Column("holder_id", sa.Uuid(), nullable=True),
        sa.Column("held_since", UTCDateTime(), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", UTCDateTime(), nullable=False),
        sa.Column("updated_at", UTCDateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["group_id"],
            ["groups.id"],
            name=op.f("fk_books_group_id_groups"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["holder_id"],
            ["users.id"],
            name=op.f("fk_books_holder_id_users"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["owner_id"],
            ["users.id"],
            name=op.f("fk_books_owner_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_books")),
    )
    with op.batch_alter_table("books", schema=None) as batch_op:
        batch_op.create_index("ix_books_group_title", ["group_id", "title"], unique=False)
        batch_op.create_index(batch_op.f("ix_books_holder_id"), ["holder_id"], unique=False)
        batch_op.create_index(batch_op.f("ix_books_owner_id"), ["owner_id"], unique=False)

    op.create_table(
        "book_queue",
        sa.Column("book_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("joined_at", UTCDateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["book_id"],
            ["books.id"],
            name=op.f("fk_book_queue_book_id_books"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_book_queue_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("book_id", "user_id", name=op.f("pk_book_queue")),
    )
    with op.batch_alter_table("book_queue", schema=None) as batch_op:
        batch_op.create_index(batch_op.f("ix_book_queue_user_id"), ["user_id"], unique=False)


def downgrade() -> None:
    with op.batch_alter_table("book_queue", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_book_queue_user_id"))
    op.drop_table("book_queue")
    with op.batch_alter_table("books", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_books_owner_id"))
        batch_op.drop_index(batch_op.f("ix_books_holder_id"))
        batch_op.drop_index("ix_books_group_title")
    op.drop_table("books")
    with op.batch_alter_table("groups", schema=None) as batch_op:
        batch_op.drop_column("kind")
