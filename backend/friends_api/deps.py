"""Shared FastAPI dependencies."""

from collections.abc import Iterator
from dataclasses import dataclass
from typing import Annotated

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from friends_api.core.config import Settings
from friends_api.core.errors import AuthError
from friends_api.core.security import AccessClaims, decode_access_token
from friends_api.features.auth.models import User
from friends_api.features.auth.service import AuthContext

_READ_ONLY_METHODS = frozenset({"GET", "HEAD", "OPTIONS"})

_bearer = HTTPBearer(auto_error=False, description="Access token from /auth/login")


def get_settings_dep(request: Request) -> Settings:
    settings: Settings = request.app.state.settings
    return settings


def get_auth_context(request: Request) -> AuthContext:
    ctx: AuthContext = request.app.state.auth
    return ctx


def get_db(request: Request) -> Iterator[Session]:
    """Read requests get a DEFERRED transaction; writes take the SQLite write lock up front.

    Services commit explicitly. Anything left uncommitted is rolled back on close.
    """
    state = request.app.state
    factory = state.read_session if request.method in _READ_ONLY_METHODS else state.write_session
    with factory() as session:
        yield session


AppSettings = Annotated[Settings, Depends(get_settings_dep)]
DbSession = Annotated[Session, Depends(get_db)]
Auth = Annotated[AuthContext, Depends(get_auth_context)]


@dataclass(frozen=True, slots=True)
class Principal:
    user: User
    claims: AccessClaims


def get_principal(
    request: Request,
    db: DbSession,
    settings: AppSettings,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> Principal:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise AuthError("Sign in to continue.")
    claims = decode_access_token(settings, credentials.credentials)
    user = db.get(User, claims.user_id)
    if user is None or not user.is_active or user.token_version != claims.token_version:
        raise AuthError("Session ended, please sign in again.")
    request.state.user_id = str(user.id)  # for the access log
    return Principal(user=user, claims=claims)


def get_current_user(principal: Annotated[Principal, Depends(get_principal)]) -> User:
    return principal.user


CurrentPrincipal = Annotated[Principal, Depends(get_principal)]
CurrentUser = Annotated[User, Depends(get_current_user)]
