"""Sign-up (contract section 4.3): creates the account and, with an invite, joins its group."""

from sqlalchemy.orm import Session

from friends_api.core.config import RegistrationMode
from friends_api.core.errors import Forbidden
from friends_api.features.auth import service
from friends_api.features.auth.schemas import AuthSession, RegisterRequest
from friends_api.features.auth.service import AuthContext
from friends_api.features.groups import service as groups_service
from friends_api.features.invites import service as invites_service
from friends_api.features.users.schemas import Me


def register(db: Session, ctx: AuthContext, body: RegisterRequest) -> AuthSession:
    if body.invite_code is None and ctx.settings.registration_mode is RegistrationMode.INVITE_ONLY:
        raise Forbidden(
            "Friends is invite-only: ask a friend for an invite link.",
            code="registration_closed",
        )
    invite = invites_service.find_by_code(db, body.invite_code) if body.invite_code else None
    if invite is not None:  # invite problems are reported before email problems
        invites_service.raise_if_unusable(invite)
        groups_service.ensure_group_has_room(db, invite.group_id)

    user = service.create_user(
        db,
        ctx,
        email=body.email,
        password=body.password,
        display_name=body.display_name,
        timezone=body.timezone,
    )
    joined = None
    if invite is not None:
        access = invites_service.join_with_invite(db, user, invite, via="register")
        joined = groups_service.to_summary(db, access.group, access.membership)
    tokens = service.start_session(db, ctx, user, body.device_label)
    db.commit()
    return AuthSession(user=Me.from_user(user), tokens=tokens, joined_group=joined)
