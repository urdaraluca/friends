from fastapi import APIRouter, Depends, status

from friends_api.core.ratelimit import limit_by_ip
from friends_api.deps import Auth, CurrentUser, DbSession
from friends_api.features.auth import registration, service
from friends_api.features.auth.schemas import (
    AuthSession,
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    TokenPair,
)
from friends_api.features.users.schemas import Me

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post(
    "/register",
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(limit_by_ip("register"))],
)
def register(body: RegisterRequest, db: DbSession, auth: Auth) -> AuthSession:
    """Creates an account. Needs an invite code unless registration is open; with a code the
    new user also joins that group (`joined_group`)."""
    return registration.register(db, auth, body)


@router.post("/login", dependencies=[Depends(limit_by_ip("login"))])
def login(body: LoginRequest, db: DbSession, auth: Auth) -> AuthSession:
    user = service.authenticate(db, auth, body.email, body.password)
    tokens = service.start_session(db, auth, user, body.device_label)
    db.commit()
    return AuthSession(user=Me.from_user(user), tokens=tokens, joined_group=None)


@router.post("/refresh", dependencies=[Depends(limit_by_ip("refresh"))])
def refresh_tokens(body: RefreshRequest, db: DbSession, auth: Auth) -> TokenPair:
    return service.refresh_session(db, auth, body.refresh_token)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(body: RefreshRequest, db: DbSession) -> None:
    """Ends the session that owns this refresh token. Always succeeds (idempotent)."""
    service.logout(db, body.refresh_token)


@router.post("/logout-all", status_code=status.HTTP_204_NO_CONTENT)
def logout_all(db: DbSession, user: CurrentUser) -> None:
    """Ends every session of the current user, including this one."""
    service.logout_everywhere(db, user)
