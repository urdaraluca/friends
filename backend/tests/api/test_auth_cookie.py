"""Cookie mode for the web app's refresh token (contract section 4.8, issue #18)."""

from collections.abc import Iterator
from typing import Any

import pytest
from fastapi.testclient import TestClient

from friends_api.api import API_PREFIX
from friends_api.core.config import Settings
from friends_api.features.auth.cookies import API_V1, REFRESH_COOKIE, TRANSPORT_HEADER
from friends_api.main import create_app
from tests.factories import DEFAULT_PASSWORD, bearer, register

COOKIE_MODE = {TRANSPORT_HEADER: "cookie"}


def set_cookie(response: Any) -> str:
    """The response's refresh ``Set-Cookie`` header (exactly one)."""
    values = [v for v in response.headers.get_list("set-cookie") if v.startswith(REFRESH_COOKIE)]
    assert len(values) == 1, values
    value: str = values[0]
    return value


def login(client: TestClient, email: str, headers: dict[str, str] | None = None) -> Any:
    return client.post(
        "/api/v1/auth/login",
        json={"email": email, "password": DEFAULT_PASSWORD},
        headers=headers or {},
    )


def test_the_api_prefix_matches() -> None:
    assert API_V1 == API_PREFIX


def test_login_puts_the_refresh_token_in_an_http_only_cookie(client: TestClient) -> None:
    account = register(client)
    client.cookies.clear()

    response = login(client, account.email, COOKIE_MODE)

    assert response.status_code == 200
    assert response.json()["tokens"]["refresh_token"] is None
    assert response.json()["tokens"]["access_token"]
    cookie = set_cookie(response)
    assert "HttpOnly" in cookie
    assert "SameSite=strict" in cookie or "SameSite=Strict" in cookie
    assert "Path=/api/v1/auth" in cookie
    assert "Secure" not in cookie  # PUBLIC_APP_URL is http in tests
    assert "Max-Age=" in cookie


def test_refresh_reads_and_rotates_the_cookie(client: TestClient) -> None:
    account = register(client)
    client.cookies.clear()
    login(client, account.email, COOKIE_MODE)
    first = client.cookies.get(REFRESH_COOKIE)

    response = client.post("/api/v1/auth/refresh", json={}, headers=COOKIE_MODE)

    assert response.status_code == 200, response.text
    assert response.json()["refresh_token"] is None
    second = client.cookies.get(REFRESH_COOKIE)
    assert second is not None
    assert second != first
    me = client.get("/api/v1/me", headers=bearer(response.json()["access_token"]))
    assert me.status_code == 200


def test_the_cookie_needs_the_header(client: TestClient) -> None:
    # A cross-site form can't send the header: the cookie alone is ignored.
    account = register(client)
    client.cookies.clear()
    login(client, account.email, COOKIE_MODE)

    response = client.post("/api/v1/auth/refresh", json={})

    assert response.status_code == 401
    assert response.json()["code"] == "refresh_invalid"


def test_body_mode_is_unchanged(client: TestClient) -> None:
    account = register(client)

    response = client.post("/api/v1/auth/refresh", json={"refresh_token": account.refresh_token})

    assert response.status_code == 200
    assert response.json()["refresh_token"]
    assert not response.headers.get_list("set-cookie")


def test_logout_revokes_the_cookie_session_and_deletes_the_cookie(client: TestClient) -> None:
    account = register(client)
    client.cookies.clear()
    login(client, account.email, COOKIE_MODE)
    stolen = client.cookies.get(REFRESH_COOKIE)

    response = client.post("/api/v1/auth/logout", json={}, headers=COOKIE_MODE)

    assert response.status_code == 204
    assert "Max-Age=0" in set_cookie(response)
    assert client.cookies.get(REFRESH_COOKIE) is None
    again = client.post("/api/v1/auth/refresh", json={"refresh_token": stolen})
    assert again.status_code == 401


def test_logout_all_and_account_deletion_delete_the_cookie(client: TestClient) -> None:
    account = register(client)
    client.cookies.clear()
    session = login(client, account.email, COOKIE_MODE).json()
    headers = {**COOKIE_MODE, **bearer(session["tokens"]["access_token"])}

    logout_all = client.post("/api/v1/auth/logout-all", headers=headers)

    assert logout_all.status_code == 204
    assert "Max-Age=0" in set_cookie(logout_all)

    session = login(client, account.email, COOKIE_MODE).json()
    headers = {**COOKIE_MODE, **bearer(session["tokens"]["access_token"])}
    deletion = client.post(
        "/api/v1/me/deletion", json={"password": DEFAULT_PASSWORD}, headers=headers
    )
    assert deletion.status_code == 204
    assert "Max-Age=0" in set_cookie(deletion)


def test_register_and_password_change_set_the_cookie(client: TestClient) -> None:
    client.cookies.clear()
    response = client.post(
        "/api/v1/auth/register",
        json={"email": "cookie@example.com", "password": DEFAULT_PASSWORD, "display_name": "C"},
        headers=COOKIE_MODE,
    )
    assert response.status_code == 201, response.text
    assert response.json()["tokens"]["refresh_token"] is None
    set_cookie(response)

    headers = {**COOKIE_MODE, **bearer(response.json()["tokens"]["access_token"])}
    changed = client.post(
        "/api/v1/me/password",
        json={"current_password": DEFAULT_PASSWORD, "new_password": "another good password"},
        headers=headers,
    )

    assert changed.status_code == 200, changed.text
    assert changed.json()["refresh_token"] is None
    set_cookie(changed)


def test_refresh_without_any_token_is_a_401(client: TestClient) -> None:
    client.cookies.clear()

    response = client.post("/api/v1/auth/refresh", json={}, headers=COOKIE_MODE)

    assert response.status_code == 401
    assert response.json()["code"] == "refresh_invalid"


@pytest.fixture
def subpath_client(settings: Settings) -> Iterator[TestClient]:
    app = create_app(settings.model_copy(update={"public_app_url": "https://example.com/friends"}))
    with TestClient(app) as client:
        yield client


def test_behind_a_subpath_the_cookie_follows_it(subpath_client: TestClient) -> None:
    account = register(subpath_client)

    response = login(subpath_client, account.email, COOKIE_MODE)

    cookie = set_cookie(response)
    assert "Path=/friends/api/v1/auth" in cookie
    assert "Secure" in cookie
