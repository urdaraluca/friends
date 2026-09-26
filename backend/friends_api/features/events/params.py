"""Calendar query parameters, shared by ``GET /groups/{group_id}/calendar`` and
``GET /me/calendar`` (contract section 5.5).

``from`` is a Python keyword, so the parameters are ``from_``/``to`` with aliases (contract
section 1.4). ``kinds`` has no default in the schema (swagger_parser can't generate one for an
enum list); omitting it means every kind, applied by the server.
"""

from typing import Annotated

from fastapi import Query

from friends_api.core.schemas import ApiDate
from friends_api.features.events.models import EventKind

FromParam = Annotated[ApiDate, Query(alias="from", description="First day (inclusive).")]
ToParam = Annotated[
    ApiDate, Query(alias="to", description="Last day (exclusive); at most 400 days after `from`.")
]
TzParam = Annotated[
    str | None,
    Query(
        description=(
            "IANA timezone for the range and the order; missing or invalid means your own "
            "(the response's `tz` says which was used)."
        )
    ),
]
KindsParam = Annotated[
    list[EventKind] | None,
    Query(
        description=(
            "Repeat the key for several. Omitted: every kind. `birthday` also covers member "
            "birthdays."
        )
    ),
]
