"""Refresh-token cookies for the web app (contract section 4.11, issue #18).

A request with ``X-Refresh-Token-Transport: cookie`` opts in. Then the refresh token travels
in an ``HttpOnly``, ``SameSite=Strict`` cookie scoped to the auth endpoints, and never in a
response body, so page scripts can't read it. Only a same-origin page can use it: the custom
header can't be sent cross-site without a CORS preflight, which production refuses, and
``SameSite=Strict`` keeps the cookie off cross-site requests anyway.
"""

from urllib.parse import urlsplit

from fastapi import Request, Response

from friends_api.core.config import Settings
from friends_api.core.db import utcnow
from friends_api.features.auth.schemas import TokenPair

REFRESH_COOKIE = "friends_refresh"
TRANSPORT_HEADER = "X-Refresh-Token-Transport"
API_V1 = "/api/v1"
"""The API prefix (``friends_api.api.API_PREFIX``; that module imports this one's routers)."""


def wants_cookie(request: Request) -> bool:
    return request.headers.get(TRANSPORT_HEADER, "").strip().lower() == "cookie"


def cookie_path(settings: Settings) -> str:
    """The auth endpoints as the browser sees them: behind ``PUBLIC_APP_URL``'s subpath."""
    return urlsplit(settings.public_app_url).path.rstrip("/") + API_V1 + "/auth"


def _secure(settings: Settings) -> bool:
    return urlsplit(settings.public_app_url).scheme == "https"


def presented_token(request: Request, body_token: str | None) -> str | None:
    """The body's refresh token, else (in cookie mode) the cookie's."""
    if body_token:
        return body_token
    return request.cookies.get(REFRESH_COOKIE) if wants_cookie(request) else None


def deliver(
    request: Request, response: Response, settings: Settings, tokens: TokenPair
) -> TokenPair:
    """``tokens`` as the client asked for them: unchanged, or with the refresh token moved into
    the cookie (the body then has ``refresh_token: null``)."""
    if not wants_cookie(request) or tokens.refresh_token is None:
        return tokens
    response.set_cookie(
        REFRESH_COOKIE,
        tokens.refresh_token,
        max_age=max(0, int((tokens.refresh_expires_at - utcnow()).total_seconds())),
        path=cookie_path(settings),
        secure=_secure(settings),
        httponly=True,
        samesite="strict",
    )
    return tokens.model_copy(update={"refresh_token": None})


def forget(request: Request, response: Response, settings: Settings) -> None:
    """Deletes the cookie (logout, logout everywhere, account deletion) in cookie mode."""
    if wants_cookie(request):
        response.delete_cookie(
            REFRESH_COOKIE,
            path=cookie_path(settings),
            secure=_secure(settings),
            httponly=True,
            samesite="strict",
        )
