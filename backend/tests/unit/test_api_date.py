from datetime import date, datetime
from typing import Any

import pytest
from pydantic import TypeAdapter, ValidationError

from friends_api.core.schemas import ApiDate

ADAPTER: TypeAdapter[date] = TypeAdapter(ApiDate)
OCT_1 = date(2026, 10, 1)


@pytest.mark.parametrize(
    "raw",
    [
        "2026-10-01",
        "2026-10-01T00:00",
        "2026-10-01T00:00Z",
        "2026-10-01T00:00:00",
        "2026-10-01T00:00:00Z",
        "2026-10-01T00:00:00.0",
        "2026-10-01T00:00:00.000",  # Dart toIso8601String() of a local midnight
        "2026-10-01T00:00:00.000Z",  # ... of a UTC midnight
        "2026-10-01T00:00:00.000000",
        "2026-10-01T00:00:00.000000Z",
        "2026-10-01 00:00",
        "2026-10-01 00:00Z",
        "2026-10-01 00:00:00",
        "2026-10-01 00:00:00.000",  # Dart toString() of a local midnight
        "2026-10-01 00:00:00.000Z",  # ... of a UTC midnight
    ],
)
def test_dates_and_midnight_date_times_are_accepted_as_is(raw: str) -> None:
    assert ADAPTER.validate_python(raw) == OCT_1


def test_the_date_part_is_never_shifted_and_output_is_a_plain_date() -> None:
    assert ADAPTER.validate_python("2024-02-29T00:00:00.000Z") == date(2024, 2, 29)
    assert ADAPTER.dump_json(OCT_1) == b'"2026-10-01"'
    assert ADAPTER.validate_python(OCT_1) == OCT_1


@pytest.mark.parametrize(
    "raw",
    [
        "2026-10-01T21:00:00Z",  # already 2 October in Bucharest
        "2026-10-01T00:00:01",
        "2026-10-01T00:00:00.001Z",
        "2026-10-01T00:30",
        "2026-10-01T12:00:00",
        "2026-10-01T00:00:00+00:00",  # explicit offsets, even zero ones
        "2026-10-01T00:00:00+03:00",
        "2026-10-01T00:00:00-05:00",
        "2026-10-01T00:00+00:00",
        "2026-10-01T00:00:00.0000000",  # more than 6 fraction digits
        "2026-10-01T00:00:00.",
        "2026-10-01T",
        "2026-10-01T00",
        "2026-10-01Z",
        "2026-10-01 ",
        " 2026-10-01",
        "2026-10-01\n",
        "2026-10-01t00:00",
        "2026-02-30",
        "2026-13-01",
        "26-10-01",
        "2026/10/01",
        "20261001",
        "",
        "2026-10-01".translate({ord("0") + d: 0x660 + d for d in range(10)}),  # Arabic-Indic digits
        1759276800,
        20261001.0,
        datetime(2026, 10, 1),  # noqa: DTZ001 - a datetime is never a date here
    ],
)
def test_anything_else_is_rejected(raw: Any) -> None:
    with pytest.raises(ValidationError):
        ADAPTER.validate_python(raw)
