"""Base models shared by every feature's request and response schemas."""

from typing import Annotated, Any, Self

from pydantic import AfterValidator, BaseModel, ConfigDict, StringConstraints, model_validator


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


Color = Annotated[
    str,
    StringConstraints(pattern=r"^#[0-9A-Fa-f]{6}$"),
    AfterValidator(str.upper),
]
"""'#RRGGBB', stored uppercase."""

Currency = Annotated[str, StringConstraints(pattern=r"^[A-Z]{3}$")]
"""ISO 4217 shape (not checked against a list)."""
