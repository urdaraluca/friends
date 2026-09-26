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


def create_group(client: TestClient, account: Account, **fields: Any) -> dict[str, Any]:
    response = client.post(
        "/api/v1/groups", headers=account.headers, json={"name": "Friends", **fields}
    )
    assert response.status_code == 201, response.text
    body: dict[str, Any] = response.json()
    return body


def create_invite(
    client: TestClient, account: Account, group_id: str, **fields: Any
) -> dict[str, Any]:
    response = client.post(
        f"/api/v1/groups/{group_id}/invites", headers=account.headers, json=fields
    )
    assert response.status_code == 201, response.text
    body: dict[str, Any] = response.json()
    return body


def join(client: TestClient, account: Account, code: str) -> dict[str, Any]:
    response = client.post(f"/api/v1/invites/{code}/accept", headers=account.headers)
    assert response.status_code == 200, response.text
    body: dict[str, Any] = response.json()
    return body


def add_member(client: TestClient, owner: Account, group_id: str) -> Account:
    """Registers a new account and joins it to the group through an invite."""
    invite = create_invite(client, owner, group_id)
    account = register(client)
    join(client, account, invite["code"])
    return account


def list_categories(client: TestClient, account: Account, group_id: str) -> list[dict[str, Any]]:
    response = client.get(f"/api/v1/groups/{group_id}/categories", headers=account.headers)
    assert response.status_code == 200, response.text
    body: list[dict[str, Any]] = response.json()
    return body


def create_category(
    client: TestClient, account: Account, group_id: str, **fields: Any
) -> dict[str, Any]:
    payload = {"name": f"Category {next(_sequence)}", **fields}
    if payload.get("parent_id") is None:
        payload.setdefault("color", "#336699")
    response = client.post(
        f"/api/v1/groups/{group_id}/categories", headers=account.headers, json=payload
    )
    assert response.status_code == 201, response.text
    body: dict[str, Any] = response.json()
    return body


def create_activity(
    client: TestClient, account: Account, group_id: str, **fields: Any
) -> dict[str, Any]:
    payload = {"title": f"Activity {next(_sequence)}", **fields}
    response = client.post(
        f"/api/v1/groups/{group_id}/activities", headers=account.headers, json=payload
    )
    assert response.status_code == 201, response.text
    body: dict[str, Any] = response.json()
    return body


ACTIVITY_WRITE_FIELDS = (
    "title",
    "description",
    "notes",
    "category_id",
    "due_date",
    "estimated_cost",
    "currency",
    "cost_per_person",
    "location_name",
    "address",
    "links",
    "attributes",
)


def activity_update(activity: dict[str, Any], **changes: Any) -> dict[str, Any]:
    """A complete PUT body built from an ``Activity`` response, with ``changes`` applied."""
    body = {field: activity[field] for field in ACTIVITY_WRITE_FIELDS}
    body["owner_id"] = activity["owner"]["id"] if activity["owner"] else None
    body["version"] = activity["version"]
    return {**body, **changes}


def create_poll(
    client: TestClient, account: Account, activity_id: str, **fields: Any
) -> dict[str, Any]:
    payload = {
        "question": f"Question {next(_sequence)}?",
        "options": [{"label": "Yes"}, {"label": "No"}],
        **fields,
    }
    response = client.post(
        f"/api/v1/activities/{activity_id}/polls", headers=account.headers, json=payload
    )
    assert response.status_code == 201, response.text
    body: dict[str, Any] = response.json()
    return body
