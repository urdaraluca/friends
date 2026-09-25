import pytest
from pydantic import ValidationError

from friends_api.core.config import AppEnv, Settings


def make(**kwargs: object) -> Settings:
    return Settings(_env_file=None, **kwargs)  # type: ignore[arg-type]


def test_prod_requires_a_real_jwt_secret() -> None:
    with pytest.raises(ValidationError, match="JWT_SECRET"):
        make(app_env=AppEnv.PROD)

    with pytest.raises(ValidationError, match="JWT_SECRET"):
        make(app_env=AppEnv.PROD, jwt_secret="too-short")

    assert make(app_env=AppEnv.PROD, jwt_secret="x" * 32).app_env is AppEnv.PROD


def test_cors_origins_are_parsed_from_csv(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CORS_ORIGINS", "https://a.example, https://b.example")

    assert make().cors_origins == ["https://a.example", "https://b.example"]


def test_localhost_cors_regex_only_in_dev() -> None:
    assert make(app_env=AppEnv.DEV).cors_origin_regex is not None
    assert make(app_env=AppEnv.TEST).cors_origin_regex is None
    assert make(app_env=AppEnv.PROD, jwt_secret="x" * 32).cors_origin_regex is None


def test_docs_are_off_in_prod_by_default() -> None:
    assert make(app_env=AppEnv.DEV).show_docs
    assert not make(app_env=AppEnv.PROD, jwt_secret="x" * 32).show_docs
    assert make(app_env=AppEnv.PROD, jwt_secret="x" * 32, docs_enabled=True).show_docs
