"""``RequestModel`` string rules (contract section 1.4)."""

import uuid
from datetime import date
from typing import Annotated, Any

import pytest
from pydantic import Field, StringConstraints, ValidationError

from friends_api.core.schemas import ApiDate, Color, Currency, RequestModel


class Body(RequestModel):
    name: Annotated[str, StringConstraints(min_length=1, max_length=20)]
    note: Annotated[str, StringConstraints(max_length=20)] | None = None
    color: Color | None = None
    currency: Currency | None = None
    due_date: ApiDate | None = None
    ref_id: uuid.UUID | None = None
    code: Currency = "EUR"
    tags: list[str] = Field(default_factory=list)


BLANKS = ["", "   ", "\t\n", "\N{NO-BREAK SPACE}\N{IDEOGRAPHIC SPACE}"]


@pytest.mark.parametrize("blank", BLANKS)
@pytest.mark.parametrize("field", ["note", "color", "currency", "due_date", "ref_id"])
def test_a_blank_optional_field_is_null_before_its_format_is_checked(
    field: str, blank: str
) -> None:
    body = Body.model_validate({"name": "x", field: blank})

    assert getattr(body, field) is None


def test_non_blank_optional_values_are_trimmed_and_validated() -> None:
    body = Body.model_validate(
        {
            "name": "  x  ",
            "note": "  hi ",
            "color": " #7e57c2 ",
            "currency": " RON ",
            "due_date": "2026-10-01",
            "ref_id": str(uuid.UUID(int=1)),
        }
    )

    assert (body.name, body.note, body.color, body.currency) == ("x", "hi", "#7E57C2", "RON")
    assert body.due_date == date(2026, 10, 1)
    assert body.ref_id == uuid.UUID(int=1)


@pytest.mark.parametrize(
    ("changes", "field"),
    [
        ({"name": "   "}, "name"),  # required: blank fails min_length
        ({"code": ""}, "code"),  # optional, but not nullable (default "EUR")
        ({"color": "#12345"}, "color"),
        ({"currency": "ron"}, "currency"),
        ({"due_date": "2026-10-01T21:00:00Z"}, "due_date"),
    ],
)
def test_other_values_still_fail_their_checks(changes: dict[str, Any], field: str) -> None:
    with pytest.raises(ValidationError) as raised:
        Body.model_validate({"name": "x", **changes})

    assert [error["loc"] for error in raised.value.errors()] == [(field,)]


def test_the_input_dict_is_not_modified() -> None:
    raw = {"name": "x", "color": ""}

    Body.model_validate(raw)

    assert raw == {"name": "x", "color": ""}


def test_nested_request_models_apply_the_rule_too() -> None:
    class Outer(RequestModel):
        items: list[Body]

    outer = Outer.model_validate({"items": [{"name": "a", "currency": ""}]})

    assert outer.items[0].currency is None


def test_input_that_is_not_an_object_is_left_to_pydantic() -> None:
    with pytest.raises(ValidationError) as raised:
        Body.model_validate(["x"])

    assert [error["type"] for error in raised.value.errors()] == ["model_type"]
