import base64
import json

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from friends_api.core.errors import Unprocessable
from friends_api.core.pagination import (
    MAX_CURSOR_LENGTH,
    MAX_OFFSET,
    decode_cursor,
    encode_cursor,
    paginate,
)
from friends_api.features.auth.models import User


def _raw_cursor(data: object) -> str:
    return base64.urlsafe_b64encode(json.dumps(data).encode()).rstrip(b"=").decode()


def test_cursor_is_unpadded_base64url_of_the_offset() -> None:
    cursor = encode_cursor(17)

    assert cursor == "eyJvIjoxN30"
    assert "=" not in cursor
    assert json.loads(base64.urlsafe_b64decode(cursor + "=")) == {"o": 17}


@pytest.mark.parametrize("offset", [0, 1, 49, 50, 12345, 10**12, 2**53])
def test_cursor_round_trip(offset: int) -> None:
    assert decode_cursor(encode_cursor(offset)) == offset


def test_no_cursor_means_the_first_page() -> None:
    assert decode_cursor(None) == 0


def test_padded_cursors_are_accepted() -> None:
    assert decode_cursor(encode_cursor(5) + "=") == 5


@pytest.mark.parametrize(
    "cursor",
    [
        "",
        "bad!",
        "eyJvIjoxN30+/",  # not the URL-safe alphabet
        "a",  # impossible length
        base64.urlsafe_b64encode(b"\xff\xfe").decode(),  # not UTF-8
        base64.urlsafe_b64encode(b"not json").decode(),
        _raw_cursor([1]),
        _raw_cursor({"x": 1}),
        _raw_cursor({"o": -1}),
        _raw_cursor({"o": 2**53 + 1}),  # too large to bind
        _raw_cursor({"o": 10**30}),
        _raw_cursor({"o": "1"}),
        _raw_cursor({"o": 1.0}),
        _raw_cursor({"o": True}),
        _raw_cursor({"o": 1, "x": 2}),
        pytest.param(  # decodes to {"o": 1}, but no valid cursor is this long
            base64.urlsafe_b64encode(b'{"o":' + b" " * 60 + b"1}").decode(), id="too-long"
        ),
        pytest.param(base64.urlsafe_b64encode(b"[" * 50_000).decode(), id="deeply-nested"),
    ],
)
def test_malformed_cursors_are_rejected(cursor: str) -> None:
    with pytest.raises(ValueError, match="invalid cursor"):
        decode_cursor(cursor)


def test_the_longest_valid_cursor_fits_the_length_limit() -> None:
    assert len(encode_cursor(MAX_OFFSET)) <= MAX_CURSOR_LENGTH


def test_a_json_recursion_error_is_an_invalid_cursor(monkeypatch: pytest.MonkeyPatch) -> None:
    """The backstop, should a short cursor ever still nest too deeply for the decoder."""

    def overflow(_: object) -> object:
        raise RecursionError("maximum recursion depth exceeded")

    monkeypatch.setattr(json, "loads", overflow)

    with pytest.raises(ValueError, match="invalid cursor"):
        decode_cursor(encode_cursor(1))


def test_paginate_reports_a_bad_cursor_on_query_cursor(db_session: Session) -> None:
    with pytest.raises(Unprocessable) as raised:
        paginate(db_session, select(User).order_by(User.id), cursor="bad!", limit=10)

    assert raised.value.code == "validation_error"
    assert raised.value.errors is not None
    assert raised.value.errors[0].field == "query.cursor"
