import uuid
from datetime import datetime
from enum import StrEnum
from typing import Annotated

from pydantic import BaseModel, StringConstraints

from friends_api.core.schemas import Color, Currency, RequestModel
from friends_api.features.groups.models import Role
from friends_api.features.users.schemas import BirthdayPublic, Timezone, UserPublic

GroupName = Annotated[str, StringConstraints(min_length=1, max_length=60)]
GroupDescription = Annotated[str, StringConstraints(max_length=500)]
Emoji = Annotated[str, StringConstraints(max_length=16)]


class AssignableRole(StrEnum):
    ADMIN = "admin"
    MEMBER = "member"


class GroupSummary(BaseModel):
    id: uuid.UUID
    name: str
    emoji: str | None
    color: str | None
    member_count: int
    my_role: Role
    created_at: datetime


class Group(GroupSummary):
    description: str | None
    currency: str
    timezone: str
    members_can_invite: bool
    created_by: UserPublic | None
    updated_at: datetime


class GroupCreate(RequestModel):
    name: GroupName
    description: GroupDescription | None = None
    emoji: Emoji | None = None
    color: Color | None = None
    currency: Currency = "EUR"
    timezone: Timezone | None = None
    """Null means the creator's timezone."""
    members_can_invite: bool = True
    seed_default_categories: bool = True


class GroupUpdate(RequestModel):
    name: GroupName
    description: GroupDescription | None = None
    emoji: Emoji | None = None
    color: Color | None = None
    currency: Currency
    timezone: Timezone
    members_can_invite: bool


class TransferOwnership(RequestModel):
    user_id: uuid.UUID


class Member(BaseModel):
    user: UserPublic
    role: Role
    joined_at: datetime
    birthday: BirthdayPublic | None
    """Null unless set and shared with the group (your own row always shows it)."""
    show_birthday: bool | None
    """Your own row: your setting. Other rows: null."""


class RoleUpdate(RequestModel):
    role: AssignableRole


class MemberSettingsUpdate(RequestModel):
    show_birthday: bool
