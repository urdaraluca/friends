"""Base models shared by every feature's request and response schemas."""

from typing import Any, Self

from pydantic import BaseModel, ConfigDict, model_validator


class RequestModel(BaseModel):
    """Request bodies: strings are trimmed, unknown fields ignored, and an optional string that
    is empty after trimming becomes ``None`` (required ones then fail their ``min_length``)."""

    model_config = ConfigDict(str_strip_whitespace=True, extra="ignore")

    @model_validator(mode="after")
    def _empty_optional_strings_to_none(self) -> Self:
        for name, field in type(self).model_fields.items():
            value: Any = getattr(self, name)
            if value == "" and not field.is_required() and field.default is None:
                setattr(self, name, None)
        return self


class ResponseModel(BaseModel):
    """Responses always include every field (``null`` when missing)."""

    model_config = ConfigDict(from_attributes=True)
