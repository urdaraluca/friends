from fastapi.testclient import TestClient


def test_errors_are_documented_as_problem_json(client: TestClient) -> None:
    schema = client.get("/api/v1/openapi.json").json()

    components = schema["components"]["schemas"]
    assert "HTTPValidationError" not in components
    assert "ValidationError" not in components
    assert {"Problem", "FieldError"} <= set(components)
    register = schema["paths"]["/api/v1/auth/register"]["post"]["responses"]
    assert register["422"]["content"] == {
        "application/problem+json": {"schema": {"$ref": "#/components/schemas/Problem"}}
    }
    assert "default" in register


def test_operation_ids_are_unique_handler_names(client: TestClient) -> None:
    schema = client.get("/api/v1/openapi.json").json()

    ids = [op["operationId"] for item in schema["paths"].values() for op in item.values()]

    assert len(ids) == len(set(ids))
    assert "list_groups" in ids
    assert "accept_invite" in ids


def test_every_operation_has_exactly_one_tag(client: TestClient) -> None:
    schema = client.get("/api/v1/openapi.json").json()

    for path, item in schema["paths"].items():
        for method, op in item.items():
            assert len(op["tags"]) == 1, (method, path)


def test_array_parameters_declare_no_default(client: TestClient) -> None:
    """swagger_parser turns an enum-list default into Dart that doesn't compile
    (``const [idea, planning]``), so list defaults are applied by the server instead."""
    schema = client.get("/api/v1/openapi.json").json()

    for path, item in schema["paths"].items():
        for method, op in item.items():
            for param in op.get("parameters", []):
                param_schema = param["schema"]
                variants = [param_schema, *param_schema.get("anyOf", [])]
                if any(v.get("type") == "array" for v in variants):
                    assert "default" not in param_schema, (method, path, param["name"])
