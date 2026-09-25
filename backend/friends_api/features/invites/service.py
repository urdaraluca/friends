"""Invite codes and joining (contract section 4.7)."""

import re
import secrets
import uuid
from datetime import timedelta

from sqlalchemy import or_, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from friends_api.core.config import Settings
from friends_api.core.db import utcnow
from friends_api.core.errors import Forbidden, Gone, NotFound
from friends_api.features.auth.models import User
from friends_api.features.group_log.service import log_event
from friends_api.features.groups import policies
from friends_api.features.groups.models import Group, Membership, Role
from friends_api.features.groups.service import GroupAccess, ensure_can_join, member_count
from friends_api.features.invites.models import Invite, InviteStatus
from friends_api.features.invites.schemas import Invite as InviteOut
from friends_api.features.invites.schemas import InviteCreate, InviteGroupPreview, InvitePreview
from friends_api.features.users.schemas import UserPublic

ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"  # Crockford base32: no I, L, O, U
CODE_LENGTH = 10
LIST_LIMIT = 100
_VALID_CODE = re.compile(r"^[0-9A-HJKMNP-TV-Z]{10}$")
_ALIASES = str.maketrans({"I": "1", "L": "1", "O": "0"})


def normalize_code(raw: str) -> str | None:
    """Uppercase, drop whitespace and dashes, map I/L to 1 and O to 0; None if malformed."""
    code = re.sub(r"[\s-]", "", raw).upper().translate(_ALIASES)
    return code if _VALID_CODE.match(code) else None


def _new_code() -> str:
    return "".join(secrets.choice(ALPHABET) for _ in range(CODE_LENGTH))


def invite_url(settings: Settings, code: str) -> str:
    return f"{settings.public_app_url}/join/{code}"


def to_invite(db: Session, settings: Settings, invite: Invite, actor: Membership) -> InviteOut:
    creator = db.get(User, invite.created_by_id) if invite.created_by_id else None
    return InviteOut(
        id=invite.id,
        group_id=invite.group_id,
        code=invite.code,
        url=invite_url(settings, invite.code),
        status=invite.status(utcnow()),
        expires_at=invite.expires_at,
        max_uses=invite.max_uses,
        use_count=invite.use_count,
        revoked_at=invite.revoked_at,
        created_by=UserPublic.from_user(creator) if creator else None,
        created_at=invite.created_at,
        can_delete=policies.can_revoke_invite(actor, invite),
    )


def create_invite(db: Session, access: GroupAccess, body: InviteCreate) -> Invite:
    actor = access.membership
    if not policies.can_create_invite(actor, access.group, never_expires=body.never_expires):
        raise Forbidden(
            "Only admins can create never-expiring invites."
            if body.never_expires and access.group.members_can_invite
            else "Only admins can invite people to this group."
        )
    expires_at = None if body.never_expires else utcnow() + timedelta(hours=body.expires_in_hours)
    for _attempt in range(5):
        invite = Invite(
            group_id=access.group.id,
            code=_new_code(),
            created_by_id=actor.user_id,
            expires_at=expires_at,
            max_uses=body.max_uses,
        )
        db.add(invite)
        try:
            with db.begin_nested():
                db.flush()
        except IntegrityError:  # code collision (about 2^-50 per pair); try another one
            continue
        log_event(
            db,
            group_id=access.group.id,
            actor_id=actor.user_id,
            action="invite.created",
            subject_type="invite",
            subject_id=invite.id,
            data={
                "max_uses": body.max_uses,
                "expires_at": expires_at.isoformat() if expires_at else None,
            },
        )
        db.commit()
        return invite
    raise RuntimeError("Could not generate a unique invite code")


def list_invites(db: Session, access: GroupAccess) -> list[Invite]:
    query = select(Invite).where(Invite.group_id == access.group.id)
    if not access.membership.is_admin:
        query = query.where(Invite.created_by_id == access.membership.user_id)
    return list(db.scalars(query.order_by(Invite.created_at.desc()).limit(LIST_LIMIT)))


def get_group_invite(db: Session, access: GroupAccess, invite_id: uuid.UUID) -> Invite:
    invite = db.get(Invite, invite_id)
    if invite is None or invite.group_id != access.group.id:
        raise NotFound("No such invite.")
    return invite


def revoke_invite(db: Session, access: GroupAccess, invite: Invite) -> None:
    if not policies.can_revoke_invite(access.membership, invite):
        raise Forbidden("You can only revoke your own invites.")
    if invite.revoked_at is None:
        invite.revoked_at = utcnow()
        log_event(
            db,
            group_id=invite.group_id,
            actor_id=access.membership.user_id,
            action="invite.revoked",
            subject_type="invite",
            subject_id=invite.id,
        )
    db.commit()


def find_by_code(db: Session, raw_code: str) -> Invite:
    code = normalize_code(raw_code)
    invite = db.scalar(select(Invite).where(Invite.code == code)) if code else None
    if invite is None:
        raise NotFound("This invite doesn't exist.")
    return invite


def preview(db: Session, invite: Invite) -> InvitePreview:
    group = db.get(Group, invite.group_id)
    assert group is not None  # noqa: S101 - invites cascade with their group
    creator = db.get(User, invite.created_by_id) if invite.created_by_id else None
    return InvitePreview(
        code=invite.code,
        status=invite.status(utcnow()),
        group=InviteGroupPreview(
            name=group.name,
            emoji=group.emoji,
            color=group.color,
            member_count=member_count(db, group.id),
        ),
        invited_by_name=creator.display_name if creator else None,
        expires_at=invite.expires_at,
    )


_GONE = {
    InviteStatus.REVOKED: ("invite_revoked", "This invite was revoked."),
    InviteStatus.EXPIRED: ("invite_expired", "This invite has expired."),
    InviteStatus.EXHAUSTED: ("invite_exhausted", "This invite has been used up."),
}


def raise_if_unusable(invite: Invite) -> None:
    status = invite.status(utcnow())
    if status is not InviteStatus.VALID:
        code, detail = _GONE[status]
        raise Gone(detail, code=code)


def join_with_invite(db: Session, user: User, invite: Invite, *, via: str) -> GroupAccess:
    """Adds ``user`` to the invite's group and consumes one use; the caller commits.

    Already a member: nothing changes and no use is consumed, whatever the invite's status.
    """
    group = db.get(Group, invite.group_id)
    assert group is not None  # noqa: S101 - invites cascade with their group
    existing = db.get(Membership, (group.id, user.id))
    if existing is not None:
        return GroupAccess(group=group, membership=existing)

    raise_if_unusable(invite)
    ensure_can_join(db, group.id, user.id)
    now = utcnow()
    consumed = db.execute(
        update(Invite)
        .where(
            Invite.id == invite.id,
            Invite.revoked_at.is_(None),
            or_(Invite.expires_at.is_(None), Invite.expires_at > now),
            or_(Invite.max_uses.is_(None), Invite.use_count < Invite.max_uses),
        )
        .values(use_count=Invite.use_count + 1, updated_at=now)
        .returning(Invite.id)
        .execution_options(synchronize_session=False)
    ).scalar_one_or_none()
    db.refresh(invite)
    if not consumed:  # lost a race for the last use, or it expired in between
        raise_if_unusable(invite)

    membership = Membership(
        group_id=group.id, user_id=user.id, role=Role.MEMBER, invite_id=invite.id
    )
    db.add(membership)
    log_event(
        db,
        group_id=group.id,
        actor_id=user.id,
        action="member.joined",
        subject_type="member",
        subject_id=user.id,
        data={"via": via, "invite_id": str(invite.id)},
    )
    db.flush()
    return GroupAccess(group=group, membership=membership)
