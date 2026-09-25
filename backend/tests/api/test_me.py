from typing import Any

import pytest
from fastapi.testclient import TestClient

from tests.factories import register

PROFILE: dict[str, Any] = {
    "display_name": "Ana",
    "birthday": {"month": 2, "day": 29},
    "timezone": "Europe/Bucharest",
    "locale": "ro-RO",
    "avatar_url": "https://example.com/ana.png",
}


def test_update_profile(client: TestClient) -> None:
    account = register(client)

    response = client.put("/api/v1/me", headers=account.headers, json=PROFILE)

    assert response.status_code == 200
    body = response.json()
    assert body["birthday"] == {"month": 2, "day": 29, "year": None}
    assert body["timezone"] == "Europe/Bucharest"
    assert client.get("/api/v1/me", headers=account.headers).json() == body


def test_birthday_can_be_cleared(client: TestClient) -> None:
    account = register(client)
    client.put("/api/v1/me", headers=account.headers, json=PROFILE)

    response = client.put("/api/v1/me", headers=account.headers, json={**PROFILE, "birthday": None})

    assert response.json()["birthday"] is None


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("birthday", {"month": 2, "day": 30}),
        ("birthday", {"month": 2, "day": 29, "year": 2025}),
        ("birthday", {"month": 13, "day": 1}),
        ("birthday", {"month": 5, "day": 1, "year": 2999}),
        ("timezone", "Europe/Atlantis"),
        ("display_name", "   "),
        ("avatar_url", "not a url"),
    ],
)
def test_invalid_profile_values_are_rejected(client: TestClient, field: str, value: Any) -> None:
    account = register(client)

    response = client.put("/api/v1/me", headers=account.headers, json={**PROFILE, field: value})

    assert response.status_code == 422, response.text
    assert response.json()["errors"][0]["field"].startswith(field)
