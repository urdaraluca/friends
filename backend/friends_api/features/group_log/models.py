import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import JSON, ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column

from friends_api.core.db import Base, IdMixin, utcnow


class GroupLog(IdMixin, Base):
    """Append-only domain events of a group (contract section 3.2).

    Written by the services in the same transaction as the change. The recap and
    notifications will be built on it; the MVP has no endpoint for it.
    """

    __tablename__ = "group_log"
    __table_args__ = (
        Index("ix_group_log_group_created", "group_id", "created_at"),
        Index("ix_group_log_group_action_created", "group_id", "action", "created_at"),
    )

    group_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("groups.id", ondelete="CASCADE"))
    actor_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), index=True
    )
    action: Mapped[str] = mapped_column(String(40))
    subject_type: Mapped[str | None] = mapped_column(String(20))
    subject_id: Mapped[uuid.UUID | None]
    """No foreign key: the subject may be deleted later."""
    data: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(default=utcnow)
