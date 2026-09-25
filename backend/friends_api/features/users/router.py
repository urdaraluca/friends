from fastapi import APIRouter

from friends_api.deps import Auth, CurrentPrincipal, CurrentUser, DbSession
from friends_api.features.auth import service as auth_service
from friends_api.features.auth.schemas import PasswordChange, TokenPair
from friends_api.features.users import service
from friends_api.features.users.schemas import Me, MeUpdate

router = APIRouter(prefix="/me", tags=["users"])


@router.get("")
def get_me(user: CurrentUser) -> Me:
    return Me.from_user(user)


@router.put("")
def update_me(body: MeUpdate, db: DbSession, user: CurrentUser) -> Me:
    service.update_profile(db, user, body)
    return Me.from_user(user)


@router.post("/password")
def change_password(
    body: PasswordChange, db: DbSession, auth: Auth, principal: CurrentPrincipal
) -> TokenPair:
    """Changes the password, signs out all other sessions and returns new tokens for this one."""
    return auth_service.change_password(
        db,
        auth,
        principal.user,
        current_password=body.current_password,
        new_password=body.new_password,
        session_id=principal.claims.session_id,
    )
