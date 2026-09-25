from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.routing import APIRoute

from friends_api.api import API_PREFIX, api_router
from friends_api.core.config import Settings, get_settings


def _operation_id(route: APIRoute) -> str:
    """Stable operationIds (the handler name) give readable generated Dart client methods."""
    return route.name


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    app = FastAPI(
        title="Friends API",
        version="1",  # API contract version; the build version is reported by /health
        openapi_url=f"{API_PREFIX}/openapi.json" if settings.show_docs else None,
        docs_url=f"{API_PREFIX}/docs" if settings.show_docs else None,
        redoc_url=None,
        generate_unique_id_function=_operation_id,
        separate_input_output_schemas=False,
    )
    app.state.settings = settings

    if settings.cors_origins or settings.cors_origin_regex:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_origin_regex=settings.cors_origin_regex,
            allow_methods=["*"],
            allow_headers=["*"],
            expose_headers=["X-Request-ID", "Retry-After"],
        )

    app.include_router(api_router)
    return app
