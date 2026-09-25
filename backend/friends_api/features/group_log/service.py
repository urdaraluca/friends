import uuid
from typing import Any

from sqlalchemy.orm import Session

from friends_api.features.group_log.models import GroupLog


def log_event(
    db: Session,
    *,
    group_id: uuid.UUID,
    actor_id: uuid.UUID | None,
    action: str,
    subject_type: str | None = None,
    subject_id: uuid.UUID | None = None,
    data: dict[str, Any] | None = None,
) -> None:
    """Records a domain event; the caller commits it together with the change."""
    db.add(
        GroupLog(
            group_id=group_id,
            actor_id=actor_id,
            action=action,
            subject_type=subject_type,
            subject_id=subject_id,
            data=data or {},
        )
    )
