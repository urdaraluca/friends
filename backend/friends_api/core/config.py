from enum import StrEnum
from functools import lru_cache
from typing import Annotated

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

DEV_JWT_SECRET = "dev-insecure-secret-change-me-dev-insecure-secret"  # noqa: S105


class AppEnv(StrEnum):
    DEV = "dev"
    TEST = "test"
    PROD = "prod"


class Settings(BaseSettings):
    """Runtime configuration, read from environment variables (and `.env` in development)."""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_env: AppEnv = AppEnv.DEV
    app_version: str = "dev"
    git_sha: str = "unknown"

    jwt_secret: str = DEV_JWT_SECRET

    docs_enabled: bool | None = None
    """Serve Swagger UI at /api/v1/docs. Defaults to on outside prod."""

    cors_origins: Annotated[list[str], NoDecode] = []
    """Comma-separated list of allowed origins. Empty in prod: the web app is same-origin."""

    log_format: str = "console"

    @field_validator("cors_origins", mode="before")
    @classmethod
    def _split_csv(cls, value: object) -> object:
        if isinstance(value, str):
            return [item.strip() for item in value.split(",") if item.strip()]
        return value

    @model_validator(mode="after")
    def _check_prod_secrets(self) -> Settings:
        if self.app_env is AppEnv.PROD and (
            self.jwt_secret == DEV_JWT_SECRET or len(self.jwt_secret.encode()) < 32
        ):
            raise ValueError("JWT_SECRET must be set to at least 32 bytes when APP_ENV=prod")
        return self

    @property
    def is_dev(self) -> bool:
        return self.app_env is AppEnv.DEV

    @property
    def show_docs(self) -> bool:
        if self.docs_enabled is not None:
            return self.docs_enabled
        return self.app_env is not AppEnv.PROD

    @property
    def cors_origin_regex(self) -> str | None:
        """Any localhost port is allowed in development only (Flutter web dev server)."""
        return r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$" if self.is_dev else None


@lru_cache
def get_settings() -> Settings:
    return Settings()
