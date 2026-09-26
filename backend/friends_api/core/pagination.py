"""Cursor pagination (contract section 1.6), shared by every paginated list.

The cursor is opaque to clients. In the MVP it is base64url (no padding) of ``{"o": <offset>}``,
so it can become keyset-based later without a client change.

Routers declare ``cursor: CursorParam = None`` and ``limit: LimitParam = DEFAULT_LIMIT``; an
invalid cursor is then a 422 ``validation_error`` on ``query.cursor``. Services page a
``select()`` that has a total, stable ``ORDER BY`` with :func:`paginate`.
"""

import base64
import binascii
import json
from typing import Annotated, Any

from fastapi import Query
from pydantic import AfterValidator
from sqlalchemy import Select
from sqlalchemy.orm import Session

from friends_api.core.errors import FieldError, Unprocessable

DEFAULT_LIMIT = 50
MAX_LIMIT = 100
MAX_OFFSET = 2**53
"""Larger offsets are rejected: SQLite can't bind integers beyond 64 bits (a crafted cursor
would otherwise be a 500), and no list gets anywhere near this long."""
MAX_CURSOR_LENGTH = 64
"""Longer cursors are rejected before decoding (the longest valid one, for ``MAX_OFFSET``, is 30
characters): a crafted, deeply nested JSON cursor would otherwise overflow the JSON decoder's
stack and be a 500."""


def encode_cursor(offset: int) -> str:
    raw = json.dumps({"o": offset}, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def decode_cursor(cursor: str | None) -> int:
    """The offset a cursor points at (0 without a cursor); ``ValueError`` if it is malformed."""
    if cursor is None:
        return 0
    if len(cursor) > MAX_CURSOR_LENGTH:
        raise ValueError("invalid cursor")
    try:
        raw = base64.b64decode(cursor + "=" * (-len(cursor) % 4), altchars=b"-_", validate=True)
        data: Any = json.loads(raw)
    # UnicodeDecodeError is a ValueError; RecursionError is a backstop for deep nesting.
    except (binascii.Error, ValueError, RecursionError) as exc:
        raise ValueError("invalid cursor") from exc
    offset = data.get("o") if isinstance(data, dict) and len(data) == 1 else None
    if type(offset) is not int or not 0 <= offset <= MAX_OFFSET:
        raise ValueError("invalid cursor")
    return offset


def _check_cursor(cursor: str | None) -> str | None:
    decode_cursor(cursor)
    return cursor


CursorParam = Annotated[
    str | None,
    Query(description="Opaque: the `next_cursor` of the previous page."),
    AfterValidator(_check_cursor),
]
LimitParam = Annotated[int, Query(ge=1, le=MAX_LIMIT)]


def paginate[T](
    db: Session, stmt: Select[tuple[T]], *, cursor: str | None, limit: int
) -> tuple[list[T], str | None]:
    """One page of ``stmt`` and the next cursor (``None`` on the last page)."""
    try:
        offset = decode_cursor(cursor)
    except ValueError as exc:
        raise Unprocessable(
            "Invalid cursor.",
            errors=[FieldError(field="query.cursor", message=str(exc), type="value_error")],
        ) from exc
    rows = list(db.scalars(stmt.offset(offset).limit(limit + 1)))
    next_cursor = encode_cursor(offset + limit) if len(rows) > limit else None
    return rows[:limit], next_cursor
