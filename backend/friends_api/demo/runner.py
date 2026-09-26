"""Runs the demo steps in order (``python -m friends_api.cli seed-demo``)."""

import random
from collections.abc import Callable
from datetime import datetime

from sqlalchemy.orm import Session

from friends_api.core.db import utcnow
from friends_api.demo.activities import add_interests, create_activities
from friends_api.demo.base import create_base
from friends_api.demo.categories import create_subcategories
from friends_api.demo.context import DEMO_SEED, DemoContext
from friends_api.demo.polls import create_polls
from friends_api.demo.wheel import create_spins
from friends_api.features.auth.service import AuthContext

Step = Callable[[Session, DemoContext], None]

STEPS: list[Step] = [
    create_subcategories,
    create_activities,
    add_interests,
    # TODO(#12): create_events (one-time, weekly, monthly, yearly, birthdays, profile birthdays)
    # -- one step per line, so parallel additions don't touch the same lines --
    create_polls,
    # -- one step per line, so parallel additions don't touch the same lines --
    create_spins,
]
"""Each step gets the session and the shared context; the runner flushes after each one."""


def seed_demo(
    db: Session, auth: AuthContext, *, now: datetime | None = None, seed: int = DEMO_SEED
) -> DemoContext:
    """Creates the demo users, their group and every step's data. The caller commits (and
    checks ``demo_users_exist`` first)."""
    ctx = create_base(db, auth, now=now or utcnow(), rng=random.Random(seed))  # noqa: S311
    for step in STEPS:
        step(db, ctx)
        db.flush()
    return ctx
