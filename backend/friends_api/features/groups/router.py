import uuid

from fastapi import APIRouter, status

from friends_api.deps import CurrentUser, DbSession, GroupMember
from friends_api.features.groups import service
from friends_api.features.groups.schemas import (
    Group,
    GroupCreate,
    GroupSummary,
    GroupUpdate,
    Member,
    MemberSettingsUpdate,
    RoleUpdate,
    TransferOwnership,
)

router = APIRouter(prefix="/groups", tags=["groups"])


@router.get("")
def list_groups(db: DbSession, user: CurrentUser) -> list[GroupSummary]:
    """My groups, by name."""
    return service.list_groups(db, user)


@router.post("", status_code=status.HTTP_201_CREATED)
def create_group(body: GroupCreate, db: DbSession, user: CurrentUser) -> Group:
    """Creates a group owned by the caller."""
    access = service.create_group(db, user, body)
    db.commit()
    return service.to_group(db, access.group, access.membership)


@router.get("/{group_id}")
def get_group(db: DbSession, access: GroupMember) -> Group:
    return service.to_group(db, access.group, access.membership)


@router.put("/{group_id}")
def update_group(body: GroupUpdate, db: DbSession, access: GroupMember) -> Group:
    service.update_group(db, access, body)
    return service.to_group(db, access.group, access.membership)


@router.delete("/{group_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_group(db: DbSession, access: GroupMember) -> None:
    service.delete_group(db, access)


@router.post("/{group_id}/transfer-ownership")
def transfer_ownership(body: TransferOwnership, db: DbSession, access: GroupMember) -> Group:
    """The target becomes owner; the caller becomes admin."""
    service.transfer_ownership(db, access, body.user_id)
    return service.to_group(db, access.group, access.membership)


@router.get("/{group_id}/members")
def list_members(db: DbSession, access: GroupMember) -> list[Member]:
    """Owner, then admins, then members; each by name."""
    return service.list_members(db, access)


@router.put("/{group_id}/members/me/settings")
def update_my_member_settings(
    body: MemberSettingsUpdate, db: DbSession, access: GroupMember
) -> Member:
    service.update_my_settings(db, access, show_birthday=body.show_birthday)
    return service.get_member(db, access, access.membership.user_id)


@router.put("/{group_id}/members/{user_id}/role")
def update_member_role(
    user_id: uuid.UUID, body: RoleUpdate, db: DbSession, access: GroupMember
) -> Member:
    service.update_member_role(db, access, user_id, body.role)
    return service.get_member(db, access, user_id)


@router.delete("/{group_id}/members/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_member(user_id: uuid.UUID, db: DbSession, access: GroupMember) -> None:
    """Removes a member, or leaves the group when ``user_id`` is the caller.

    The only member leaving deletes the group.
    """
    service.remove_member(db, access, user_id)
