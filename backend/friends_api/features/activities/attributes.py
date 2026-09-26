"""Custom-field values of activities (contract sections 6.3 and 6.4).

Pure functions over ``FieldDef`` lists; the service supplies a category's effective definitions.
"""

import math
from collections.abc import Mapping, Sequence
from typing import Any

from friends_api.core.errors import FieldError, Unprocessable
from friends_api.core.schemas import is_http_url
from friends_api.features.activities.schemas import CardAttribute
from friends_api.features.categories.schemas import (
    RATING_MAX,
    RATING_MIN,
    YEAR_MAX,
    YEAR_MIN,
    FieldDef,
    FieldType,
)

TEXT_MAX_LENGTH = 200
LONG_TEXT_MAX_LENGTH = 5000

_MESSAGES = {
    "wrong_type": "This value has the wrong type for the field.",
    "too_long": "This text is too long.",
    "out_of_range": "This number is out of range.",
    "too_many_decimals": "A rating has at most one decimal.",
    "invalid_url": "This must be an absolute http(s) URL.",
    "not_an_option": "This is not one of the field's options.",
    "unknown_key": "The category has no field with this key.",
}


def _is_number(value: Any) -> bool:
    # bool is a subclass of int, so it is excluded explicitly.
    return isinstance(value, int | float) and not isinstance(value, bool)


def _is_finite(value: int | float) -> bool:
    try:
        return math.isfinite(value)
    except OverflowError:  # a JSON integer too large for a float is out of range too
        return False


def is_cleared(value: Any) -> bool:
    """``null`` and ``""`` clear a key."""
    return value is None or (isinstance(value, str) and not value.strip())


def _check_text(value: Any, max_length: int) -> tuple[Any, str | None]:
    if not isinstance(value, str):
        return None, "wrong_type"
    value = value.strip()
    return (None, "too_long") if len(value) > max_length else (value, None)


def _check_number(field_def: FieldDef, value: Any) -> tuple[Any, str | None]:
    if not _is_number(value):
        return None, "wrong_type"
    if not _is_finite(value):
        return None, "out_of_range"
    if (field_def.min is not None and value < field_def.min) or (
        field_def.max is not None and value > field_def.max
    ):
        return None, "out_of_range"
    return value, None


def _check_rating(field_def: FieldDef, value: Any) -> tuple[Any, str | None]:
    if not _is_number(value):
        return None, "wrong_type"
    low = field_def.min if field_def.min is not None else RATING_MIN
    high = field_def.max if field_def.max is not None else RATING_MAX
    if not _is_finite(value) or not low <= value <= high:
        return None, "out_of_range"
    if round(value * 10) != value * 10:
        return None, "too_many_decimals"
    return value, None


def _check_url(value: Any) -> tuple[Any, str | None]:
    if not isinstance(value, str):
        return None, "wrong_type"
    value = value.strip()
    return (value, None) if is_http_url(value) else (None, "invalid_url")


def _check_select(field_def: FieldDef, value: Any) -> tuple[Any, str | None]:
    if not isinstance(value, str):
        return None, "wrong_type"
    value = value.strip()
    return (value, None) if value in (field_def.options or []) else (None, "not_an_option")


def _check_year(value: Any) -> tuple[Any, str | None]:
    if not isinstance(value, int) or isinstance(value, bool):  # floats are rejected too
        return None, "wrong_type"
    return (value, None) if YEAR_MIN <= value <= YEAR_MAX else (None, "out_of_range")


def check_value(field_def: FieldDef, value: Any) -> tuple[Any, str | None]:
    """The value to store (strings trimmed), or ``(None, reason)`` when it is invalid.

    ``value`` must not be a clearing value (see :func:`is_cleared`)."""
    match field_def.type:
        case FieldType.TEXT:
            return _check_text(value, TEXT_MAX_LENGTH)
        case FieldType.LONG_TEXT:
            return _check_text(value, LONG_TEXT_MAX_LENGTH)
        case FieldType.NUMBER:
            return _check_number(field_def, value)
        case FieldType.RATING:
            return _check_rating(field_def, value)
        case FieldType.URL:
            return _check_url(value)
        case FieldType.SELECT:
            return _check_select(field_def, value)
        case FieldType.YEAR:
            return _check_year(value)


def validate_attributes(
    values: Mapping[str, Any], field_defs: Sequence[FieldDef]
) -> dict[str, Any]:
    """Strict validation for a write. Every bad key is reported in one 422
    ``invalid_attributes``. Returns what to store: no cleared keys, in definition order."""
    defs = {field_def.key: field_def for field_def in field_defs}
    accepted: dict[str, Any] = {}
    errors: list[FieldError] = []
    for key, value in values.items():
        if is_cleared(value):
            continue
        field_def = defs.get(key)
        reason: str | None
        if field_def is None:
            reason = "unknown_key"
        else:
            value, reason = check_value(field_def, value)
            if reason is None:
                accepted[key] = value
        if reason is not None:
            errors.append(
                FieldError(field=f"attributes.{key}", message=_MESSAGES[reason], type=reason)
            )
    if errors:
        raise Unprocessable(
            "Some attributes don't match the category's fields.",
            code="invalid_attributes",
            errors=errors,
        )
    return {key: accepted[key] for key in defs if key in accepted}


def visible_attributes(stored: Mapping[str, Any], field_defs: Sequence[FieldDef]) -> dict[str, Any]:
    """Read filtering: a stored value is returned only while its key is in the current
    definitions and the value still validates against them (GET never writes)."""
    visible: dict[str, Any] = {}
    for field_def in field_defs:
        if field_def.key in stored and not is_cleared(stored[field_def.key]):
            value, reason = check_value(field_def, stored[field_def.key])
            if reason is None:
                visible[field_def.key] = value
    return visible


def card_attributes(
    visible: Mapping[str, Any], field_defs: Sequence[FieldDef]
) -> list[CardAttribute]:
    """The visible values whose definition has ``show_on_card``, in definition order."""
    return [
        CardAttribute(
            key=field_def.key,
            label=field_def.label,
            type=field_def.type,
            value=visible[field_def.key],
        )
        for field_def in field_defs
        if field_def.show_on_card and field_def.key in visible
    ]
