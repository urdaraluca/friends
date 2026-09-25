from fastapi.testclient import TestClient


def test_health_reports_ok_and_version(client: TestClient) -> None:
    response = client.get("/api/v1/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "version": "test"}


def test_openapi_uses_handler_names_as_operation_ids(client: TestClient) -> None:
    schema = client.get("/api/v1/openapi.json").json()

    assert schema["paths"]["/api/v1/health"]["get"]["operationId"] == "get_health"
