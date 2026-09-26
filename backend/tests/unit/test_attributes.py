from typing import Any

import pytest

from friends_api.core.errors import Unprocessable
from friends_api.features.activities.attributes import (
    card_attributes,
    check_value,
    validate_attributes,
    visible_attributes,
)
from friends_api.features.categories.defaults import MOVIE_NIGHT_FIELD_DEFS
from friends_api.features.categories.schemas import FieldDef

MOVIE_DEFS = [FieldDef.model_validate(raw) for raw in MOVIE_NIGHT_FIELD_DEFS]


def field(type_: str, **extra: Any) -> FieldDef:
    return FieldDef.model_validate({"key": "k", "label": "K", "type": type_, **extra})


SELECT = {"options": ["Easy", "Hard"]}


@pytest.mark.parametrize(
    ("field_def", "value", "stored"),
    [
        (field("text"), "  hello ", "hello"),
        (field("text"), "x" * 200, "x" * 200),
        (field("long_text"), "y" * 5000, "y" * 5000),
        (field("number"), 3, 3),
        (field("number"), -2.5, -2.5),
        (field("number", min=1, max=600), 600, 600),
        (field("number"), 10**20, 10**20),
        (field("rating"), 0, 0),
        (field("rating"), 7.5, 7.5),
        (field("rating"), 10, 10),
        (field("rating", min=1, max=5), 4.5, 4.5),
        (
            field("url"),
            "https://www.imdb.com/title/tt0111161/",
            "https://www.imdb.com/title/tt0111161/",
        ),
        (field("url"), "HTTP://example.com", "HTTP://example.com"),
        (field("select", **SELECT), "Hard", "Hard"),
        (field("select", **SELECT), " Easy ", "Easy"),
        (field("year"), 1800, 1800),
        (field("year"), 2200, 2200),
    ],
)
def test_valid_values(field_def: FieldDef, value: Any, stored: Any) -> None:
    assert check_value(field_def, value) == (stored, None)


@pytest.mark.parametrize(
    ("field_def", "value", "reason"),
    [
        (field("text"), 5, "wrong_type"),
        (field("text"), "x" * 201, "too_long"),
        (field("long_text"), ["a"], "wrong_type"),
        (field("long_text"), "y" * 5001, "too_long"),
        (field("number"), "3", "wrong_type"),
        (field("number"), True, "wrong_type"),
        (field("number"), float("nan"), "out_of_range"),
        (field("number"), float("inf"), "out_of_range"),
        (field("number"), 10**400, "out_of_range"),  # too large for a float: not a 500
        (field("rating"), 10**400, "out_of_range"),
        (field("number", min=1, max=600), 0, "out_of_range"),
        (field("number", min=1, max=600), 600.5, "out_of_range"),
        (field("rating"), False, "wrong_type"),
        (field("rating"), "7", "wrong_type"),
        (field("rating"), 11, "out_of_range"),
        (field("rating"), -0.5, "out_of_range"),
        (field("rating", min=1, max=5), 5.5, "out_of_range"),
        (field("rating"), 7.25, "too_many_decimals"),
        (field("url"), 42, "wrong_type"),
        (field("url"), "www.imdb.com", "invalid_url"),
        (field("url"), "ftp://example.com/file", "invalid_url"),
        (field("url"), "https://", "invalid_url"),
        (field("url"), "https://exa mple.com", "invalid_url"),
        (field("url"), "https://example.com:port/", "invalid_url"),
        (field("url"), "https://example.com/" + "a" * 2048, "invalid_url"),
        (field("select", **SELECT), 1, "wrong_type"),
        (field("select", **SELECT), "easy", "not_an_option"),  # case-sensitive
        (field("year"), 2001.0, "wrong_type"),
        (field("year"), "2001", "wrong_type"),
        (field("year"), True, "wrong_type"),
        (field("year"), 1799, "out_of_range"),
        (field("year"), 2201, "out_of_range"),
    ],
)
def test_invalid_values(field_def: FieldDef, value: Any, reason: str) -> None:
    assert check_value(field_def, value) == (None, reason)


def test_every_one_decimal_rating_is_accepted() -> None:
    imdb_rating = MOVIE_DEFS[1]
    # As parsed from JSON: 0.0, 0.1, ..., 0.7, ..., 1.1, ..., 10.0.
    values = [float(f"{tenths // 10}.{tenths % 10}") for tenths in range(101)]

    assert [check_value(imdb_rating, value) for value in values] == [(v, None) for v in values]


def test_every_bad_key_is_reported_at_once() -> None:
    with pytest.raises(Unprocessable) as raised:
        validate_attributes(
            {"imdb_rating": 11, "year": True, "genre": "Drama", "nope": 1, "runtime_min": 7.25},
            MOVIE_DEFS,
        )

    assert raised.value.code == "invalid_attributes"
    assert [(e.field, e.type) for e in raised.value.errors or []] == [
        ("attributes.imdb_rating", "out_of_range"),
        ("attributes.year", "wrong_type"),
        ("attributes.nope", "unknown_key"),
    ]


def test_null_and_empty_strings_clear_keys_and_values_come_back_in_definition_order() -> None:
    stored = validate_attributes(
        {"year": 1999, "genre": "", "imdb_url": None, "imdb_rating": 8, "unknown": None},
        MOVIE_DEFS,
    )

    assert stored == {"imdb_rating": 8, "year": 1999}
    assert list(stored) == ["imdb_rating", "year"]


def test_read_filtering_hides_unknown_and_stale_values() -> None:
    stored = {
        "genre": "Western",
        "imdb_rating": 7.5,
        "year": 2001,
        "gone": "x",
        "runtime_min": None,
    }

    visible = visible_attributes(stored, MOVIE_DEFS)

    assert visible == {"imdb_rating": 7.5, "year": 2001}  # "Western" is not an option any more


def test_card_attributes_are_the_visible_show_on_card_values() -> None:
    visible = {"genre": "Drama", "imdb_rating": 7.5, "year": 2001}

    cards = card_attributes(visible, MOVIE_DEFS)

    assert [card.model_dump() for card in cards] == [
        {"key": "imdb_rating", "label": "IMDb rating", "type": "rating", "value": 7.5}
    ]
    assert card_attributes({"genre": "Drama"}, MOVIE_DEFS) == []
