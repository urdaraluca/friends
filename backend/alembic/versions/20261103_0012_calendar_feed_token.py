"""calendar feed token

Revision ID: 0012
Revises: 0011
Create Date: 2026-11-03 12:00:00.000000

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0012"
down_revision: str | Sequence[str] | None = "0011"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.add_column(sa.Column("calendar_feed_token", sa.String(length=64), nullable=True))
        batch_op.create_index(
            batch_op.f("ix_users_calendar_feed_token"), ["calendar_feed_token"], unique=True
        )


def downgrade() -> None:
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_users_calendar_feed_token"))
        batch_op.drop_column("calendar_feed_token")
