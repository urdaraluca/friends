"""Error types and RFC 9457 ``application/problem+json`` responses.

Every error body looks like::

    {"type": "urn:friends:problem:<code>", "title": ..., "status": 404, "detail": ...,
     "code": "<code>", "errors": [{"field", "message", "type"}]?, "request_id": ...}

``code`` is the stable, machine-readable value clients switch on.
"""

import logging
from collections.abc import Mapping, Sequence
from http import HTTPStatus
from typing import Any, cast

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from friends_api.core.logging import request_id_var

logger = logging.getLogger(__name__)

PROBLEM_CONTENT_TYPE = "application/problem+json"


class FieldError(BaseModel):
    field: str
    message: str
    type: str


class Problem(BaseModel):
    type: str
    title: str
    status: int
    detail: str | None = None
    code: str
    errors: list[FieldError] | None = None
    request_id: str | None = None


class AppError(Exception):
    """Base class for errors that map to a problem+json response."""

    status_code: int = 400
    code: str = "bad_request"

    def __init__(
        self,
        detail: str | None = None,
        *,
        code: str | None = None,
        errors: Sequence[FieldError] | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> None:
        super().__init__(detail or code or self.code)
        self.detail = detail
        if code is not None:
            self.code = code
        self.errors = list(errors) if errors is not None else None
        self.headers = dict(headers or {})


class Unauthenticated(AppError):
    status_code = 401
    code = "unauthenticated"

    def __init__(self, detail: str | None = None, *, code: str | None = None) -> None:
        super().__init__(detail, code=code, headers={"WWW-Authenticate": "Bearer"})


class Forbidden(AppError):
    status_code = 403
    code = "forbidden"


class NotFound(AppError):
    status_code = 404
    code = "not_found"


class Conflict(AppError):
    status_code = 409
    code = "conflict"


class Gone(AppError):
    status_code = 410
    code = "gone"


class ValidationFailed(AppError):
    status_code = 422
    code = "validation_error"


class RateLimited(AppError):
    status_code = 429
    code = "rate_limited"

    def __init__(self, retry_after_seconds: int) -> None:
        super().__init__(
            "Too many requests, try again later.",
            headers={"Retry-After": str(max(1, retry_after_seconds))},
        )


def problem_response(
    status: int,
    code: str,
    *,
    detail: str | None = None,
    errors: Sequence[FieldError] | None = None,
    headers: Mapping[str, str] | None = None,
) -> JSONResponse:
    problem = Problem(
        type=f"urn:friends:problem:{code}",
        title=HTTPStatus(status).phrase,
        status=status,
        detail=detail,
        code=code,
        errors=list(errors) if errors is not None else None,
        request_id=request_id_var.get(),
    )
    return JSONResponse(
        problem.model_dump(exclude_none=True),
        status_code=status,
        headers=dict(headers or {}),
        media_type=PROBLEM_CONTENT_TYPE,
    )


_HTTP_STATUS_CODES = {
    400: "bad_request",
    401: "unauthenticated",
    403: "forbidden",
    404: "not_found",
    405: "method_not_allowed",
    409: "conflict",
    413: "payload_too_large",
    415: "unsupported_media_type",
    429: "rate_limited",
}


def _field_path(loc: Sequence[Any]) -> str:
    # Drop the leading "body" / "query" / "path" segment: clients map errors onto form fields.
    parts = [str(part) for part in loc]
    if parts and parts[0] in {"body", "query", "path", "header", "cookie"}:
        parts = parts[1:]
    return ".".join(parts)


async def _app_error_handler(_request: Request, exc: Exception) -> JSONResponse:
    exc = cast(AppError, exc)
    return problem_response(
        exc.status_code, exc.code, detail=exc.detail, errors=exc.errors, headers=exc.headers
    )


async def _validation_error_handler(_request: Request, exc: Exception) -> JSONResponse:
    exc = cast(RequestValidationError, exc)
    # Never echo "input"/"ctx": they can contain passwords.
    errors = [
        FieldError(field=_field_path(err["loc"]), message=err["msg"], type=err["type"])
        for err in exc.errors()
    ]
    return problem_response(422, "validation_error", detail="Invalid request.", errors=errors)


async def _http_exception_handler(_request: Request, exc: Exception) -> JSONResponse:
    exc = cast(StarletteHTTPException, exc)
    code = _HTTP_STATUS_CODES.get(exc.status_code, "http_error")
    detail = exc.detail if isinstance(exc.detail, str) else None
    return problem_response(exc.status_code, code, detail=detail, headers=exc.headers)


def register_exception_handlers(app: FastAPI) -> None:
    app.add_exception_handler(AppError, _app_error_handler)
    app.add_exception_handler(RequestValidationError, _validation_error_handler)
    app.add_exception_handler(StarletteHTTPException, _http_exception_handler)


class CatchAllMiddleware:
    """Turns unhandled exceptions into a problem+json 500.

    It sits *inside* the CORS middleware, so browsers can read the error body.
    """

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        response_started = False

        async def send_tracking(message: Message) -> None:
            nonlocal response_started
            if message["type"] == "http.response.start":
                response_started = True
            await send(message)

        try:
            await self.app(scope, receive, send_tracking)
        except Exception:
            logger.exception("Unhandled error")
            if response_started:
                raise
            response = problem_response(500, "internal_error", detail="Something went wrong.")
            await response(scope, receive, send)
