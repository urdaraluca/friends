"""Logging setup and the request-ID / access-log middleware."""

import json
import logging
import re
import time
import uuid
from contextvars import ContextVar
from datetime import UTC, datetime
from typing import Any

from starlette.datastructures import MutableHeaders
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from friends_api.core.config import LogFormat

request_id_var: ContextVar[str | None] = ContextVar("request_id", default=None)

REQUEST_ID_HEADER = "X-Request-ID"
_VALID_REQUEST_ID = re.compile(r"^[A-Za-z0-9._-]{1,64}$")

access_logger = logging.getLogger("friends_api.access")


class _RequestIdFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = request_id_var.get() or "-"
        return True


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "ts": datetime.fromtimestamp(record.created, UTC).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
            "request_id": getattr(record, "request_id", "-"),
        }
        extra = getattr(record, "extra_fields", None)
        if isinstance(extra, dict):
            payload.update(extra)
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False)


def configure_logging(log_format: LogFormat, level: str = "INFO") -> None:
    handler = logging.StreamHandler()
    handler.addFilter(_RequestIdFilter())
    if log_format is LogFormat.JSON:
        handler.setFormatter(JsonFormatter())
    else:
        handler.setFormatter(
            logging.Formatter("%(asctime)s %(levelname)-7s [%(request_id)s] %(name)s: %(message)s")
        )
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(level.upper())


class RequestContextMiddleware:
    """Assigns a request ID (echoed as X-Request-ID), marks API responses `no-store`, and writes
    one access-log line per request."""

    def __init__(self, app: ASGIApp, *, quiet_paths: frozenset[str] = frozenset()) -> None:
        self.app = app
        self.quiet_paths = quiet_paths

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        incoming = dict(scope["headers"]).get(REQUEST_ID_HEADER.lower().encode(), b"").decode()
        request_id = incoming if _VALID_REQUEST_ID.match(incoming) else uuid.uuid4().hex
        token = request_id_var.set(request_id)
        is_api = scope["path"].startswith("/api/")
        started = time.perf_counter()
        status_code = 500

        async def send_with_request_id(message: Message) -> None:
            nonlocal status_code
            if message["type"] == "http.response.start":
                status_code = message["status"]
                headers = MutableHeaders(scope=message)
                headers[REQUEST_ID_HEADER] = request_id
                if is_api and "cache-control" not in headers:
                    headers["Cache-Control"] = "no-store"
            await send(message)

        try:
            await self.app(scope, receive, send_with_request_id)
        finally:
            if scope["path"] not in self.quiet_paths:
                duration_ms = round((time.perf_counter() - started) * 1000, 1)
                client = scope.get("client")
                client_ip = client[0] if client else "-"
                # Set by the auth dependency via request.state (shared scope["state"] dict).
                user_id = scope.get("state", {}).get("user_id", "-")
                access_logger.info(
                    "%s %s %s %sms ip=%s user=%s",
                    scope["method"],
                    scope["path"],
                    status_code,
                    duration_ms,
                    client_ip,
                    user_id,
                    extra={
                        "extra_fields": {
                            "method": scope["method"],
                            "path": scope["path"],
                            "status": status_code,
                            "duration_ms": duration_ms,
                            "client_ip": client_ip,
                            "user_id": user_id,
                        }
                    },
                )
            request_id_var.reset(token)
