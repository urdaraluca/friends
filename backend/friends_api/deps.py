"""Shared FastAPI dependencies."""

from collections.abc import Iterator
from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy.orm import Session

from friends_api.core.config import Settings

_READ_ONLY_METHODS = frozenset({"GET", "HEAD", "OPTIONS"})


def get_settings_dep(request: Request) -> Settings:
    settings: Settings = request.app.state.settings
    return settings


def get_db(request: Request) -> Iterator[Session]:
    """Read requests get a DEFERRED transaction; writes take the SQLite write lock up front.

    Services commit explicitly. Anything left uncommitted is rolled back on close.
    """
    state = request.app.state
    factory = state.read_session if request.method in _READ_ONLY_METHODS else state.write_session
    with factory() as session:
        yield session


AppSettings = Annotated[Settings, Depends(get_settings_dep)]
DbSession = Annotated[Session, Depends(get_db)]
