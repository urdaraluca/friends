from fastapi.testclient import TestClient


def test_health_reports_ok_version_and_db(client: TestClient) -> None:
    response = client.get("/api/v1/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "version": "test", "db": "ok"}


def test_every_response_carries_a_request_id(client: TestClient) -> None:
    generated = client.get("/api/v1/health").headers["X-Request-ID"]
    echoed = client.get("/api/v1/health", headers={"X-Request-ID": "abc-123"})
    replaced = client.get("/api/v1/health", headers={"X-Request-ID": "bad id with spaces"})

    assert len(generated) == 32
    assert echoed.headers["X-Request-ID"] == "abc-123"
    assert replaced.headers["X-Request-ID"] != "bad id with spaces"


def test_openapi_uses_handler_names_as_operation_ids(client: TestClient) -> None:
    schema = client.get("/api/v1/openapi.json").json()

    assert schema["paths"]["/api/v1/health"]["get"]["operationId"] == "get_health"
