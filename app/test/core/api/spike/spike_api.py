"""Wire-rule spike API (ADR 0003): the wire shapes later milestones need, built the way the
backend builds them (same FastAPI settings, same ``install_openapi`` post-processing).

Writes ``spike_openapi.json`` next to this file. Run from ``backend/`` (``PYTHONPATH=.`` makes
``friends_api`` importable from a script outside the package):

    PYTHONPATH=. uv run python ../app/test/core/api/spike/spike_api.py

then regenerate the Dart client from ``app/`` (see README.md).
"""

import json
import uuid
from datetime import date
from enum import StrEnum
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, FastAPI, Query
from pydantic import AwareDatetime, BaseModel

from friends_api.core.openapi import install_openapi
from friends_api.core.schemas import RequestModel


class ActivityStatus(StrEnum):
    IDEA = "idea"
    PLANNING = "planning"
    SCHEDULED = "scheduled"
    DONE = "done"
    DROPPED = "dropped"


class EventKind(StrEnum):
    ONE_TIME = "one_time"
    RECURRING = "recurring"
    BIRTHDAY = "birthday"


class ActivitySort(StrEnum):
    CREATED_AT = "created_at"
    DUE_DATE = "due_date"
    TITLE = "title"


class SpikeWrite(RequestModel):
    title: str
    status: ActivityStatus = ActivityStatus.IDEA
    due_date: date | None = None
    starts_at: AwareDatetime | None = None
    notes: str | None = None


class SpikeItem(BaseModel):
    id: uuid.UUID
    title: str
    status: ActivityStatus
    due_date: date | None
    starts_at: AwareDatetime | None
    notes: str | None


router = APIRouter(prefix="/api/v1", tags=["spike"])


@router.get("/spike/items")
def list_spike_items(
    from_: Annotated[date, Query(alias="from")],
    status: Annotated[list[ActivityStatus] | None, Query()] = None,
    kinds: Annotated[list[EventKind] | None, Query()] = None,
    due_before: date | None = None,
    changed_after: AwareDatetime | None = None,
    sort: ActivitySort = ActivitySort.CREATED_AT,
    include_subcategories: bool = True,
) -> list[SpikeItem]:
    return []


@router.put("/spike/items/{item_id}")
def update_spike_item(item_id: uuid.UUID, body: SpikeWrite) -> SpikeItem:
    raise NotImplementedError


app = FastAPI(
    title="Friends wire-rule spike",
    version="1",
    generate_unique_id_function=lambda route: route.name,
    separate_input_output_schemas=False,
)
install_openapi(app)
app.include_router(router)

if __name__ == "__main__":
    output = Path(__file__).with_name("spike_openapi.json")
    schema = json.dumps(app.openapi(), indent=2, ensure_ascii=False) + "\n"
    output.write_text(schema, encoding="utf-8", newline="\n")
    print(f"Spike schema written to {output}")
