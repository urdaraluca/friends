from enum import StrEnum
from functools import lru_cache
from pathlib import Path
from typing import Annotated

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

DEV_JWT_SECRET = "dev-insecure-secret-change-me-dev-insecure-secret"  # noqa: S105
LOCALHOST_ORIGIN_REGEX = r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"


class AppEnv(StrEnum):
    DEV = "dev"
    TEST = "test"
    PROD = "prod"


class LogFormat(StrEnum):
    CONSOLE = "console"
    JSON = "json"


class RegistrationMode(StrEnum):
    INVITE_ONLY = "invite_only"
    OPEN = "open"


class Settings(BaseSettings):
    """Runtime configuration from environment variables (and `.env` in development).

    See docs/api/contract.md section 1.11 for the full table.
    """

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_env: AppEnv = AppEnv.DEV
    app_version: str = "dev"
    git_sha: str = "unknown"

    database_url: str = "sqlite:///./friends.db"
    sqlite_busy_timeout_ms: int = 5000
    backup_dir: Path = Path("./backups")
    backup_keep: int = 14

    jwt_secret: str = DEV_JWT_SECRET
    access_token_ttl_minutes: int = 15
    refresh_token_ttl_days: int = 30
    """Sliding lifetime of a refresh token; every refresh extends it..."""
    refresh_session_max_days: int = 180
    """...up to this absolute cap after login, then the user signs in again."""
    refresh_reuse_grace_seconds: int = 60
    """A just-rotated refresh token may be presented again (lost response) within this window."""

    argon2_time_cost: int = 3
    argon2_memory_kib: int = 65536
    argon2_parallelism: int = 4

    registration_mode: RegistrationMode = RegistrationMode.INVITE_ONLY
    public_app_url: str = "http://localhost:5000"
    """Base of invite links: {PUBLIC_APP_URL}/join/{code}. No trailing slash."""
    rate_limit_enabled: bool = True

    web_dir: Path = Path("/app/web")
    """The Flutter web build, served at / when index.html exists there."""
    android_cert_sha256: Annotated[list[str], NoDecode] = []
    """Signing-certificate fingerprints for /.well-known/assetlinks.json (App Links)."""

    docs_enabled: bool | None = None
    """Serve Swagger UI at /api/v1/docs. Defaults to on outside prod."""

    cors_origins: Annotated[list[str], NoDecode] = []
    """Comma-separated list of allowed origins. Empty in prod: the web app is same-origin."""

    log_format: LogFormat = LogFormat.CONSOLE
    log_level: str = "INFO"

    @field_validator("cors_origins", "android_cert_sha256", mode="before")
    @classmethod
    def _split_csv(cls, value: object) -> object:
        if isinstance(value, str):
            return [item.strip() for item in value.split(",") if item.strip()]
        return value

    @field_validator("public_app_url")
    @classmethod
    def _strip_trailing_slash(cls, value: str) -> str:
        return value.rstrip("/")

    @model_validator(mode="after")
    def _check_prod_settings(self) -> Settings:
        if self.app_env is AppEnv.PROD:
            if self.jwt_secret == DEV_JWT_SECRET or len(self.jwt_secret.encode()) < 32:
                raise ValueError("JWT_SECRET must be set to at least 32 bytes when APP_ENV=prod")
            if not self.public_app_url or "localhost" in self.public_app_url:
                raise ValueError("PUBLIC_APP_URL must be set when APP_ENV=prod")
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
        return LOCALHOST_ORIGIN_REGEX if self.is_dev else None


@lru_cache
def get_settings() -> Settings:
    return Settings()
