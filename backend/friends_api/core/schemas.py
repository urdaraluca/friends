"""Base models and value types shared by every feature's request and response schemas."""

import re
from datetime import date, datetime
from typing import Annotated, Any
from urllib.parse import urlsplit

from pydantic import (
    AfterValidator,
    BaseModel,
    BeforeValidator,
    ConfigDict,
    StringConstraints,
    model_validator,
)


class RequestModel(BaseModel):
    """Request bodies (contract section 1.4): strings are trimmed, unknown fields ignored.

    A string that is empty after trimming, sent for an optional field (one whose default is
    ``None``), becomes ``None`` *before* the field is validated, so it never trips a format
    check: ``""`` for a ``Color``, ``Currency``, ``ApiDate`` or ID means null. Required fields
    are left alone, so a blank required string still fails its ``min_length``.
    """

    model_config = ConfigDict(str_strip_whitespace=True, extra="ignore")

    @model_validator(mode="before")
    @classmethod
    def _blank_optional_strings_to_none(cls, data: Any) -> Any:
        if not isinstance(data, dict):
            return data
        blank = [
            key
            for name, field in cls.model_fields.items()
            if not field.is_required()
            and field.default is None
            and isinstance(value := data.get(key := field.alias or name), str)
            and not value.strip()  # str.strip() removes at least what str_strip_whitespace does
        ]
        return {**data, **dict.fromkeys(blank)} if blank else data


Color = Annotated[
    str,
    StringConstraints(pattern=r"^#[0-9A-Fa-f]{6}$"),
    AfterValidator(str.upper),
]
"""'#RRGGBB', stored uppercase."""

Currency = Annotated[str, StringConstraints(pattern=r"^[A-Z]{3}$")]
"""ISO 4217 shape (not checked against a list)."""


# --- dates (contract section 1.3) ---------------------------------------------------------

_API_DATE = re.compile(
    r"([0-9]{4}-[0-9]{2}-[0-9]{2})(?:[T ]00:00(?::00(?:\.0{1,6})?)?Z?)?", re.ASCII
)


def parse_api_date(value: Any) -> Any:
    """``YYYY-MM-DD``, or a *midnight* date-time (``T`` or space separator, optional zero
    fraction, optional ``Z``) whose date part is taken as is, never converted between zones.

    Any other time and any explicit offset other than ``Z`` are rejected: a UTC instant like
    ``2026-10-01T21:00:00Z`` is already 2 October in Bucharest, so it can't name a date.
    """
    if isinstance(value, datetime):  # a date subclass: never truncate one silently
        raise ValueError("expected a date, not a date-time")
    if isinstance(value, date):
        return value
    if not isinstance(value, str):
        raise ValueError("expected a date string (YYYY-MM-DD)")
    match = _API_DATE.fullmatch(value)
    if match is None:
        raise ValueError("expected YYYY-MM-DD or a midnight date-time")
    return date.fromisoformat(match.group(1))  # ValueError for impossible dates (2026-02-30)


ApiDate = Annotated[date, BeforeValidator(parse_api_date)]
"""A floating calendar date on the wire (``due_date``, ``due_before``, ...); output is always
``YYYY-MM-DD``."""


# --- URLs (contract section 1.4) ----------------------------------------------------------

MAX_URL_LENGTH = 2048
_WHITESPACE_OR_CONTROL = re.compile(r"[\s\x00-\x1f\x7f]")


def is_http_url(value: str) -> bool:
    """An absolute ``http``/``https`` URL with a host, at most 2048 characters."""
    if len(value) > MAX_URL_LENGTH or _WHITESPACE_OR_CONTROL.search(value):
        return False
    try:
        parts = urlsplit(value)
        _ = parts.port  # raises ValueError for a malformed port
    except ValueError:
        return False
    return parts.scheme.lower() in ("http", "https") and bool(parts.hostname)


def _check_http_url(value: str) -> str:
    if not is_http_url(value):
        raise ValueError("must be an absolute http(s) URL")
    return value


HttpUrlStr = Annotated[
    str, StringConstraints(max_length=MAX_URL_LENGTH), AfterValidator(_check_http_url)
]
"""An absolute http(s) URL with a host (links, poll option URLs), stored as given."""
