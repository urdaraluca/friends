"""Group feed schemas (contract section 15)."""

import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel

from friends_api.features.users.schemas import UserPublic


class FeedItem(BaseModel):
    """One ``group_log`` row, as members see it."""

    id: uuid.UUID
    action: str
    """A ``group_log`` action (contract section 3.2); only those in section 15 appear."""
    actor: UserPublic | None
    """Null for a deleted account."""
    subject_type: str | None
    subject_id: uuid.UUID | None
    subject_title: str | None
    """The subject's current title, question or name; the logged one once it is deleted."""
    subject_exists: bool
    """Whether the subject can still be opened."""
    data: dict[str, Any]
    """The action's details that members may see (section 15)."""
    created_at: datetime


class FeedPage(BaseModel):
    items: list[FeedItem]
    """Newest first."""
    next_cursor: str | None
