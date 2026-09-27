from fastapi import APIRouter, Depends, Request, Response, status

from friends_api.core.ratelimit import limit_by_ip
from friends_api.deps import AppSettings, Auth, CurrentUser, DbSession
from friends_api.features.auth import cookies, registration, service
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
def register(
    body: RegisterRequest, db: DbSession, auth: Auth, request: Request, response: Response
) -> AuthSession:
    """Creates an account. Needs an invite code unless registration is open; with a code the
    new user also joins that group (`joined_group`)."""
    session = registration.register(db, auth, body)
    tokens = cookies.deliver(request, response, auth.settings, session.tokens)
    return session.model_copy(update={"tokens": tokens})


@router.post("/login", dependencies=[Depends(limit_by_ip("login"))])
def login(
    body: LoginRequest, db: DbSession, auth: Auth, request: Request, response: Response
) -> AuthSession:
    user = service.authenticate(db, auth, body.email, body.password)
    tokens = service.start_session(db, auth, user, body.device_label)
    db.commit()
    return AuthSession(
        user=Me.from_user(user),
        tokens=cookies.deliver(request, response, auth.settings, tokens),
        joined_group=None,
    )


@router.post("/refresh", dependencies=[Depends(limit_by_ip("refresh"))])
def refresh_tokens(
    body: RefreshRequest, db: DbSession, auth: Auth, request: Request, response: Response
) -> TokenPair:
    """Rotates the refresh token. In cookie mode (``X-Refresh-Token-Transport: cookie``) the
    token comes from the refresh cookie and the new one goes back into it."""
    presented = cookies.presented_token(request, body.refresh_token)
    if presented is None:
        raise service.refresh_invalid()
    tokens = service.refresh_session(db, auth, presented)
    return cookies.deliver(request, response, auth.settings, tokens)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(
    body: RefreshRequest,
    db: DbSession,
    settings: AppSettings,
    request: Request,
    response: Response,
) -> None:
    """Ends the session that owns this refresh token (or the refresh cookie's). Always
    succeeds (idempotent)."""
    presented = cookies.presented_token(request, body.refresh_token)
    if presented is not None:
        service.logout(db, presented)
    cookies.forget(request, response, settings)


@router.post("/logout-all", status_code=status.HTTP_204_NO_CONTENT)
def logout_all(
    db: DbSession, user: CurrentUser, settings: AppSettings, request: Request, response: Response
) -> None:
    """Ends every session of the current user, including this one."""
    service.logout_everywhere(db, user)
    cookies.forget(request, response, settings)
