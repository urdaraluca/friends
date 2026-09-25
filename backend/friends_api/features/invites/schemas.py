import uuid
from datetime import datetime

from pydantic import BaseModel, Field

from friends_api.core.schemas import RequestModel
from friends_api.features.invites.models import InviteStatus
from friends_api.features.users.schemas import UserPublic


class Invite(BaseModel):
    id: uuid.UUID
    group_id: uuid.UUID
    code: str
    url: str
    status: InviteStatus
    expires_at: datetime | None
    max_uses: int | None
    use_count: int
    revoked_at: datetime | None
    created_by: UserPublic | None
    created_at: datetime
    can_delete: bool


class InviteCreate(RequestModel):
    expires_in_hours: int = Field(default=168, ge=1, le=720)
    never_expires: bool = False
    """Admin+ only; expires_in_hours is then ignored."""
    max_uses: int | None = Field(default=None, ge=1, le=100)
    """Null = unlimited."""


class InviteGroupPreview(BaseModel):
    name: str
    emoji: str | None
    color: str | None
    member_count: int


class InvitePreview(BaseModel):
    """Public: carries no IDs."""

    code: str
    status: InviteStatus
    group: InviteGroupPreview
    invited_by_name: str | None
    expires_at: datetime | None
