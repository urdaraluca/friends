"""email and push: verification, reset tokens, notification preferences, deliveries, push
subscriptions

Revision ID: 0013
Revises: 0012
Create Date: 2026-11-04 12:00:00.000000

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

from friends_api.core.db import UTCDateTime

# revision identifiers, used by Alembic.
revision: str = "0013"
down_revision: str | Sequence[str] | None = "0012"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_NOTIFY = (
    "notify_polls",
    "notify_wheel",
    "notify_reminders",
    "notify_members",
    "notify_plans",
)


def upgrade() -> None:
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.add_column(sa.Column("email_verified_at", UTCDateTime(), nullable=True))
        for name in _NOTIFY:
            batch_op.add_column(
                sa.Column(name, sa.Boolean(), nullable=False, server_default=sa.true())
            )
        batch_op.add_column(
            sa.Column("notify_email", sa.Boolean(), nullable=False, server_default=sa.false())
        )
    with op.batch_alter_table("memberships", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column(
                "notifications_muted", sa.Boolean(), nullable=False, server_default=sa.false()
            )
        )

    op.create_table(
        "email_tokens",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("purpose", sa.String(length=20), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("email", sa.String(length=254), nullable=False),
        sa.Column("expires_at", UTCDateTime(), nullable=False),
        sa.Column("used_at", UTCDateTime(), nullable=True),
        sa.Column("created_at", UTCDateTime(), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.CheckConstraint(
            "purpose IN ('verify_email', 'reset_password')", name=op.f("ck_email_tokens_purpose")
        ),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_email_tokens_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_email_tokens")),
        sa.UniqueConstraint("token_hash", name=op.f("uq_email_tokens_token_hash")),
    )
    with op.batch_alter_table("email_tokens", schema=None) as batch_op:
        batch_op.create_index(batch_op.f("ix_email_tokens_user_id"), ["user_id"], unique=False)

    op.create_table(
        "notification_deliveries",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("channel", sa.String(length=10), nullable=False),
        sa.Column("kind", sa.String(length=20), nullable=False),
        sa.Column("ref", sa.String(length=100), nullable=False),
        sa.Column("created_at", UTCDateTime(), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_notification_deliveries_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_notification_deliveries")),
        sa.UniqueConstraint(
            "user_id", "channel", "kind", "ref", name="uq_notification_deliveries_unique"
        ),
    )
    with op.batch_alter_table("notification_deliveries", schema=None) as batch_op:
        batch_op.create_index(
            "ix_notification_deliveries_created_at", ["created_at"], unique=False
        )


    op.create_table(
        "push_subscriptions",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("endpoint", sa.String(length=1000), nullable=False),
        sa.Column("p256dh", sa.String(length=200), nullable=False),
        sa.Column("auth", sa.String(length=100), nullable=False),
        sa.Column("created_at", UTCDateTime(), nullable=False),
        sa.Column("last_used_at", UTCDateTime(), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_push_subscriptions_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_push_subscriptions")),
        sa.UniqueConstraint("endpoint", name=op.f("uq_push_subscriptions_endpoint")),
    )
    with op.batch_alter_table("push_subscriptions", schema=None) as batch_op:
        batch_op.create_index(
            batch_op.f("ix_push_subscriptions_user_id"), ["user_id"], unique=False
        )


def downgrade() -> None:
    with op.batch_alter_table("push_subscriptions", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_push_subscriptions_user_id"))
    op.drop_table("push_subscriptions")
    with op.batch_alter_table("memberships", schema=None) as batch_op:
        batch_op.drop_column("notifications_muted")
    with op.batch_alter_table("notification_deliveries", schema=None) as batch_op:
        batch_op.drop_index("ix_notification_deliveries_created_at")
    op.drop_table("notification_deliveries")
    with op.batch_alter_table("email_tokens", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_email_tokens_user_id"))
    op.drop_table("email_tokens")
    with op.batch_alter_table("users", schema=None) as batch_op:
        for name in ("notify_email", *reversed(_NOTIFY), "email_verified_at"):
            batch_op.drop_column(name)
