from typing import Any

import pytest
from fastapi import APIRouter, FastAPI
from fastapi.testclient import TestClient
from pydantic import BaseModel, Field

from friends_api.core.config import Settings
from friends_api.core.errors import Conflict
from friends_api.main import create_app

PROBLEM = "application/problem+json"


class Payload(BaseModel):
    email: str
    password: str = Field(min_length=10)


def _app_with_test_routes(settings: Settings) -> FastAPI:
    app = create_app(settings)
    router = APIRouter(prefix="/api/v1/_test", tags=["test"])

    @router.post("/echo")
    def echo(payload: Payload) -> dict[str, Any]:
        return payload.model_dump()

    @router.get("/conflict")
    def conflict() -> None:
        raise Conflict("Somebody else changed this.", code="version_conflict")

    @router.get("/boom")
    def boom() -> None:
        raise RuntimeError("kaboom")

    app.include_router(router)
    return app


@pytest.fixture
def test_client(settings: Settings) -> TestClient:
    return TestClient(_app_with_test_routes(settings))


def test_unknown_route_is_a_problem_404(test_client: TestClient) -> None:
    response = test_client.get("/api/v1/nope")

    assert response.status_code == 404
    assert response.headers["content-type"] == PROBLEM
    body = response.json()
    assert body["code"] == "not_found"
    assert body["type"] == "urn:friends:problem:not_found"
    assert body["title"] == "Not Found"
    assert body["request_id"] == response.headers["X-Request-ID"]


def test_wrong_method_is_a_problem_405(test_client: TestClient) -> None:
    response = test_client.delete("/api/v1/health")

    assert response.status_code == 405
    assert response.json()["code"] == "method_not_allowed"


def test_validation_errors_list_fields_without_echoing_input(test_client: TestClient) -> None:
    response = test_client.post(
        "/api/v1/_test/echo", json={"email": "a@example.com", "password": "short-pw"}
    )

    assert response.status_code == 422
    body = response.json()
    assert body["code"] == "validation_error"
    assert body["errors"] == [
        {
            "field": "password",
            "message": "String should have at least 10 characters",
            "type": "string_too_short",
        }
    ]
    assert "short-pw" not in response.text


def test_app_errors_keep_their_code(test_client: TestClient) -> None:
    response = test_client.get("/api/v1/_test/conflict")

    assert response.status_code == 409
    assert response.json()["code"] == "version_conflict"
    assert response.json()["detail"] == "Somebody else changed this."


def test_unhandled_errors_become_a_problem_500(test_client: TestClient) -> None:
    response = test_client.get("/api/v1/_test/boom")

    assert response.status_code == 500
    assert response.headers["content-type"] == PROBLEM
    assert response.json()["code"] == "internal_error"
    assert "kaboom" not in response.text
