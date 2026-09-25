"""Permission rules (contract section 7.2).

The same functions enforce the rules in the services and compute the ``can_*`` flags in
responses, so the UI and the server never disagree.
"""

from friends_api.features.groups.models import Group, Membership, Role
from friends_api.features.invites.models import Invite


def can_edit_group(actor: Membership) -> bool:
    return actor.is_admin


def can_delete_group(actor: Membership) -> bool:
    return actor.is_owner


def can_manage_roles(actor: Membership) -> bool:
    """Change roles and transfer ownership."""
    return actor.is_owner


def can_remove_member(actor: Membership, target: Membership) -> bool:
    """Removing someone else (leaving is always allowed, see the service)."""
    if target.role is Role.OWNER:
        return False
    if target.role is Role.ADMIN:
        return actor.is_owner
    return actor.is_admin


def can_create_invite(actor: Membership, group: Group, *, never_expires: bool) -> bool:
    if never_expires:
        return actor.is_admin
    return actor.is_admin or group.members_can_invite


def can_see_invite(actor: Membership, invite: Invite) -> bool:
    return actor.is_admin or invite.created_by_id == actor.user_id


def can_revoke_invite(actor: Membership, invite: Invite) -> bool:
    return can_see_invite(actor, invite)
