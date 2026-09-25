"""Helpers that create data through the public API."""

from dataclasses import dataclass
from itertools import count
from typing import Any

from fastapi.testclient import TestClient

DEFAULT_PASSWORD = "correct horse battery"
_sequence = count(1)


@dataclass
class Account:
    id: str
    email: str
    password: str
    access_token: str
    refresh_token: str
    body: dict[str, Any]

    @property
    def headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.access_token}"}


def register(
    client: TestClient,
    *,
    email: str | None = None,
    password: str = DEFAULT_PASSWORD,
    display_name: str | None = None,
    **extra: Any,
) -> Account:
    n = next(_sequence)
    email = email or f"user{n}@example.com"
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": password,
            "display_name": display_name or f"User {n}",
            **extra,
        },
    )
    assert response.status_code == 201, response.text
    body = response.json()
    return Account(
        id=body["user"]["id"],
        email=body["user"]["email"],
        password=password,
        access_token=body["tokens"]["access_token"],
        refresh_token=body["tokens"]["refresh_token"],
        body=body,
    )


def login(client: TestClient, email: str, password: str = DEFAULT_PASSWORD) -> dict[str, Any]:
    response = client.post("/api/v1/auth/login", json={"email": email, "password": password})
    assert response.status_code == 200, response.text
    body: dict[str, Any] = response.json()
    return body


def bearer(access_token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {access_token}"}
