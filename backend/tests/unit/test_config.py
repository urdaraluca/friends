from typing import Any

import pytest
from pydantic import ValidationError

from friends_api.core.config import AppEnv, Settings

PROD: dict[str, Any] = {
    "app_env": AppEnv.PROD,
    "jwt_secret": "x" * 32,
    "public_app_url": "https://friends.example.com/",
}


def make(**kwargs: Any) -> Settings:
    return Settings(_env_file=None, **kwargs)


def test_prod_requires_a_real_jwt_secret() -> None:
    with pytest.raises(ValidationError, match="JWT_SECRET"):
        make(**{**PROD, "jwt_secret": make().jwt_secret})

    with pytest.raises(ValidationError, match="JWT_SECRET"):
        make(**{**PROD, "jwt_secret": "too-short"})

    assert make(**PROD).app_env is AppEnv.PROD


def test_prod_requires_the_public_app_url() -> None:
    with pytest.raises(ValidationError, match="PUBLIC_APP_URL"):
        make(**{**PROD, "public_app_url": "http://localhost:5000"})

    assert make(**PROD).public_app_url == "https://friends.example.com"


def test_csv_settings_are_parsed(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CORS_ORIGINS", "https://a.example, https://b.example")
    monkeypatch.setenv("ANDROID_CERT_SHA256", "AA:BB,CC:DD")

    settings = make()

    assert settings.cors_origins == ["https://a.example", "https://b.example"]
    assert settings.android_cert_sha256 == ["AA:BB", "CC:DD"]


def test_localhost_cors_regex_only_in_dev() -> None:
    assert make(app_env=AppEnv.DEV).cors_origin_regex is not None
    assert make(app_env=AppEnv.TEST).cors_origin_regex is None
    assert make(**PROD).cors_origin_regex is None


def test_docs_are_off_in_prod_by_default() -> None:
    assert make(app_env=AppEnv.DEV).show_docs
    assert not make(**PROD).show_docs
    assert make(**PROD, docs_enabled=True).show_docs
