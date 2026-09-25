"""OpenAPI post-processing for clean client generation (contract section 12).

Every operation documents its errors as ``Problem`` (``application/problem+json``), including
422, and FastAPI's default ``HTTPValidationError`` / ``ValidationError`` schemas are removed.
"""

from typing import Any

from fastapi import FastAPI
from fastapi.openapi.utils import get_openapi

from friends_api.core.errors import PROBLEM_CONTENT_TYPE, Problem

_PROBLEM_REF = {"$ref": "#/components/schemas/Problem"}
_PROBLEM_RESPONSE = {
    "description": "Error (RFC 9457 problem details)",
    "content": {PROBLEM_CONTENT_TYPE: {"schema": _PROBLEM_REF}},
}


def build_openapi(app: FastAPI) -> dict[str, Any]:
    schema = get_openapi(
        title=app.title,
        version=app.version,
        routes=app.routes,
        separate_input_output_schemas=app.separate_input_output_schemas,
    )
    components = schema.setdefault("components", {}).setdefault("schemas", {})
    components.pop("HTTPValidationError", None)
    components.pop("ValidationError", None)
    problem_schema = Problem.model_json_schema(ref_template="#/components/schemas/{model}")
    components.update(problem_schema.pop("$defs", {}))
    components["Problem"] = problem_schema

    for path_item in schema.get("paths", {}).values():
        for operation in path_item.values():
            responses: dict[str, Any] = operation.setdefault("responses", {})
            responses.pop("422", None)
            if operation.get("parameters") or operation.get("requestBody"):
                responses["422"] = _PROBLEM_RESPONSE
            responses["default"] = _PROBLEM_RESPONSE
    return schema


def install_openapi(app: FastAPI) -> None:
    def openapi() -> dict[str, Any]:
        if app.openapi_schema is None:
            app.openapi_schema = build_openapi(app)
        return app.openapi_schema

    app.openapi = openapi  # type: ignore[method-assign]
