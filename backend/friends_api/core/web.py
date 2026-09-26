"""Same-origin hosting of the Flutter web build and the App Links file (contract section 1.1).

The API routers are matched first. Whatever they don't match is handled here:

1. any other ``/api/...`` path, as sent or once normalised (``//api/...``, ``/./api/...``):
   problem+json 404. A known API path with the wrong method never gets here, because the router
   answers it with a 405 itself;
2. ``/.well-known/assetlinks.json``: a normal route, hidden from the OpenAPI schema;
3. ``GET``/``HEAD`` from ``WEB_DIR``, only when ``WEB_DIR/index.html`` exists: an existing file as
   is; otherwise ``index.html`` (SPA fallback) if the last segment of the normalised path has no
   ``.``; otherwise 404. Every response from ``WEB_DIR`` is ``Cache-Control: no-cache`` and
   carries the security headers (``WEB_SECURITY_HEADERS``: a strict Content-Security-Policy);
4. any other method: 405.

uvicorn passes paths on as sent, so they are normalised here the way the file lookup resolves them:
empty and ``.`` segments dropped, ``..`` resolved.

The fallback is the router's ``default`` handler rather than a catch-all route: a catch-all route
would fully match ``POST /api/v1/health`` and hide the router's 405.
"""

import errno
import os
import posixpath
import stat
from pathlib import Path
from typing import Any

from fastapi import FastAPI
from fastapi.responses import JSONResponse
from starlette._utils import get_route_path
from starlette.concurrency import run_in_threadpool
from starlette.exceptions import HTTPException
from starlette.responses import Response
from starlette.staticfiles import StaticFiles
from starlette.types import Receive, Scope, Send
from starlette.websockets import WebSocketClose

from friends_api.core.config import Settings

API_ROOT = "/api"
ANDROID_PACKAGE_NAME = "io.github.urdaraluca.friends"
ASSET_LINKS_PATH = "/.well-known/assetlinks.json"
INDEX_FILE = "index.html"
WEB_CACHE_CONTROL = "no-cache"
"""On every response from ``WEB_DIR``. A Flutter web build names its files without a content hash
(``flutter_bootstrap.js`` loads ``main.dart.js``, ``canvaskit/`` and ``assets/`` by fixed names), so
browsers must revalidate each one (a 304 while unchanged): a copy cached heuristically, from its
``Last-Modified``, could outlive a release."""

CONTENT_SECURITY_POLICY = "; ".join(
    [
        "default-src 'self'",
        # No inline or eval'd scripts; CanvasKit compiles WebAssembly.
        "script-src 'self' 'wasm-unsafe-eval'",
        # Flutter sets inline styles on the elements it creates.
        "style-src 'self' 'unsafe-inline'",
        # Avatars are external https URLs (contract section 3); CanvasKit fetches images and
        # its fallback fonts (emoji, other scripts) from fonts.gstatic.com.
        "img-src 'self' data: blob: https:",
        "font-src 'self' data: https://fonts.gstatic.com",
        "connect-src 'self' https:",
        "worker-src 'self' blob:",
        "manifest-src 'self'",
        "object-src 'none'",
        "base-uri 'self'",
        "form-action 'self'",
        "frame-ancestors 'none'",
    ]
)
"""For the web build: the app can't be framed, and only its own scripts run."""

WEB_SECURITY_HEADERS = {
    "Content-Security-Policy": CONTENT_SECURITY_POLICY,
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "strict-origin-when-cross-origin",
    "X-Frame-Options": "DENY",
}
"""On every response from ``WEB_DIR``, next to ``Cache-Control``."""

_STATIC_METHODS = ("GET", "HEAD")


def normalize_path(path: str) -> str:
    """``path`` as the file lookup resolves it: empty and ``.`` segments dropped, ``..`` resolved."""
    return posixpath.normpath("/" + path.lstrip("/"))


def _is_under_api(path: str) -> bool:
    return path == API_ROOT or path.startswith(API_ROOT + "/")


def is_api_path(path: str) -> bool:
    """``/api`` and everything below it belongs to the API, which never answers with HTML.

    Both the path as sent and the normalised path count: ``//api/v1/health`` (a base URL ending in
    ``/``) or ``/./api/v1/health`` match no API route, but must not get the app shell either.
    """
    return _is_under_api(path) or _is_under_api(normalize_path(path))


def asset_links(fingerprints: list[str]) -> list[dict[str, Any]]:
    """The Digital Asset Links statement that lets the Android app open this host's links."""
    return [
        {
            "relation": ["delegate_permission/common.handle_all_urls"],
            "target": {
                "namespace": "android_app",
                "package_name": ANDROID_PACKAGE_NAME,
                "sha256_cert_fingerprints": list(fingerprints),
            },
        }
    ]


class _WebFiles(StaticFiles):
    def lookup_path(self, path: str) -> tuple[str, os.stat_result | None]:
        try:
            return super().lookup_path(path)
        except OSError as exc:
            # A name the OS can't look up at all (e.g. "a*b" on Windows) is simply not a file,
            # rather than a 500.
            if exc.errno in (errno.EINVAL, errno.ENAMETOOLONG):
                return "", None
            raise


class WebFallback:
    """ASGI app for every request that no route matched (steps 1, 3 and 4 above)."""

    def __init__(self, web_dir: Path) -> None:
        # Only its path lookup and file responses are used (it is never called as an ASGI app),
        # so the directory may be missing (dev, tests).
        self.files = _WebFiles(directory=web_dir, check_dir=False)

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":  # nothing here speaks WebSocket
            await WebSocketClose()(scope, receive, send)
            return
        path = get_route_path(scope)
        if is_api_path(path):
            raise HTTPException(status_code=404)
        if scope["method"] not in _STATIC_METHODS:
            raise HTTPException(status_code=405, headers={"Allow": ", ".join(_STATIC_METHODS)})
        response = await self._static_response(path, scope)
        await response(scope, receive, send)

    async def _static_response(self, path: str, scope: Scope) -> Response:
        index_path, index_stat = await run_in_threadpool(self.files.lookup_path, INDEX_FILE)
        if index_stat is None or not stat.S_ISREG(index_stat.st_mode):
            raise HTTPException(status_code=404)  # no web build: static hosting is off

        try:
            response = await self.files.get_response(self.files.get_path(scope), scope)
        except HTTPException as exc:
            # Missing files and directories (including "/") get the app shell, unless the last
            # segment looks like a file name: a missing asset stays a 404.
            if exc.status_code != 404 or "." in posixpath.basename(normalize_path(path)):
                raise
            response = self.files.file_response(index_path, index_stat, scope)
        # Files, the app shell and their 304s alike, whatever spelling of the path was used.
        response.headers["Cache-Control"] = WEB_CACHE_CONTROL
        response.headers.update(WEB_SECURITY_HEADERS)
        return response


def install_web(app: FastAPI, settings: Settings) -> None:
    """Adds ``/.well-known/assetlinks.json`` and the web fallback. Call after the API routers."""
    fingerprints = list(settings.android_cert_sha256)

    async def get_asset_links() -> JSONResponse:
        if not fingerprints:
            raise HTTPException(status_code=404, detail="ANDROID_CERT_SHA256 is not set.")
        return JSONResponse(asset_links(fingerprints))

    app.add_api_route(
        ASSET_LINKS_PATH,
        get_asset_links,
        methods=list(_STATIC_METHODS),
        include_in_schema=False,
        tags=["web"],
    )
    app.router.default = WebFallback(settings.web_dir)
