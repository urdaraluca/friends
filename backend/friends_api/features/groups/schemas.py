import unicodedata
import uuid
from datetime import datetime
from enum import StrEnum
from typing import Annotated

from pydantic import AfterValidator, BaseModel, StringConstraints

from friends_api.core.schemas import Color, Currency, RequestModel
from friends_api.features.groups.models import GroupKind, Role
from friends_api.features.users.schemas import BirthdayPublic, Timezone, UserPublic

GroupName = Annotated[str, StringConstraints(min_length=1, max_length=60)]
GroupDescription = Annotated[str, StringConstraints(max_length=500)]
_ZWJ = 0x200D
_KEYCAP = 0x20E3
_KEYCAP_BASES = frozenset("0123456789#*")


def _is_extender(code: int) -> bool:
    """Code points that belong to the emoji before them: variation selectors, skin tones,
    tag characters (subdivision flags), the keycap and other combining marks."""
    return (
        0xFE00 <= code <= 0xFE0F
        or 0x1F3FB <= code <= 0x1F3FF
        or 0xE0020 <= code <= 0xE007F
        or unicodedata.category(chr(code)).startswith("M")
    )


def _is_regional_indicator(code: int) -> bool:
    return 0x1F1E6 <= code <= 0x1F1FF


def emoji_clusters(text: str) -> list[str]:
    """``text`` split into emoji-sized clusters: a base character with its extenders, a ZWJ
    sequence (👩‍💻) or a pair of regional indicators (a flag). Close enough to Unicode grapheme
    clusters for one emoji, without a segmentation library."""
    clusters: list[str] = []
    joining = pairing_flag = False
    for char in text:
        code = ord(char)
        if clusters and (code == _ZWJ or _is_extender(code) or joining):
            clusters[-1] += char
            joining = code == _ZWJ
            continue
        if clusters and pairing_flag and _is_regional_indicator(code):
            clusters[-1] += char
            pairing_flag = False
            continue
        clusters.append(char)
        pairing_flag = _is_regional_indicator(code)
    return clusters


def _one_emoji(value: str) -> str:
    """Contract section 9: a group's emoji is exactly one emoji, which may be a sequence."""
    clusters = emoji_clusters(value)
    if len(clusters) != 1:
        raise ValueError("Use a single emoji.")
    cluster = clusters[0]
    base = cluster[0]
    keycap = base in _KEYCAP_BASES and chr(_KEYCAP) in cluster
    if not keycap and unicodedata.category(base) != "So":
        raise ValueError("Use a single emoji.")
    return value


Emoji = Annotated[str, StringConstraints(max_length=16), AfterValidator(_one_emoji)]
"""One emoji (a ZWJ sequence, a flag or a keycap counts as one), at most 16 characters."""


class AssignableRole(StrEnum):
    ADMIN = "admin"
    MEMBER = "member"


class GroupSummary(BaseModel):
    id: uuid.UUID
    name: str
    emoji: str | None
    color: str | None
    member_count: int
    kind: GroupKind
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
    kind: GroupKind = GroupKind.GENERAL
    seed_default_categories: bool = True
    """Seeds the categories for ``kind`` (contract sections 6.5 and 17.1)."""


class GroupUpdate(RequestModel):
    name: GroupName
    description: GroupDescription | None = None
    emoji: Emoji | None = None
    color: Color | None = None
    currency: Currency
    timezone: Timezone
    kind: GroupKind | None = None
    """Null keeps it. A new kind changes the tabs, not the categories."""
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
