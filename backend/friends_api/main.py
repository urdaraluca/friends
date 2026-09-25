from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.routing import APIRoute

from friends_api.api import API_PREFIX, api_router
from friends_api.core.config import Settings, get_settings
from friends_api.core.db import create_db_engine, create_session_factories
from friends_api.core.errors import CatchAllMiddleware, register_exception_handlers
from friends_api.core.logging import REQUEST_ID_HEADER, RequestContextMiddleware, configure_logging
from friends_api.core.ratelimit import RateLimits
from friends_api.core.security import Passwords
from friends_api.features.auth.service import AuthContext


def _operation_id(route: APIRoute) -> str:
    """Stable operationIds (the handler name) give readable generated Dart client methods."""
    return route.name


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    configure_logging(settings.log_format, settings.log_level)

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        engine = create_db_engine(
            settings.database_url, busy_timeout_ms=settings.sqlite_busy_timeout_ms
        )
        app.state.engine = engine
        app.state.read_session, app.state.write_session = create_session_factories(engine)
        try:
            yield
        finally:
            engine.dispose()

    app = FastAPI(
        title="Friends API",
        version="1",  # API contract version; the build version is reported by /health
        openapi_url=f"{API_PREFIX}/openapi.json" if settings.show_docs else None,
        docs_url=f"{API_PREFIX}/docs" if settings.show_docs else None,
        redoc_url=None,
        generate_unique_id_function=_operation_id,
        separate_input_output_schemas=False,
        lifespan=lifespan,
    )
    app.state.settings = settings
    app.state.auth = AuthContext(settings=settings, passwords=Passwords(settings))
    app.state.rate_limits = RateLimits()

    register_exception_handlers(app)
    # Middleware added later wraps the earlier ones: RequestContext > CORS > CatchAll > app.
    app.add_middleware(CatchAllMiddleware)
    if settings.cors_origins or settings.cors_origin_regex:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_origin_regex=settings.cors_origin_regex,
            allow_credentials=False,
            allow_methods=["GET", "POST", "PUT", "DELETE"],
            allow_headers=["Authorization", "Content-Type", REQUEST_ID_HEADER],
            expose_headers=[REQUEST_ID_HEADER, "Retry-After"],
            max_age=600,
        )
    app.add_middleware(RequestContextMiddleware, quiet_paths=frozenset({f"{API_PREFIX}/health"}))

    app.include_router(api_router)
    return app
