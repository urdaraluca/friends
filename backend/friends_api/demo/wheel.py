"""A few demo wheel spins, some of them accepted."""

from dataclasses import dataclass
from datetime import timedelta

from sqlalchemy.orm import Session

from friends_api.demo.context import DemoContext
from friends_api.features.activities.models import Activity, ActivityStatus
from friends_api.features.wheel import service as wheel_service
from friends_api.features.wheel.schemas import SpinCreate, WheelFilters


@dataclass(frozen=True, slots=True)
class DemoSpin:
    spinner: int
    """Index into ``ctx.users``."""
    filters: WheelFilters
    hours_ago: float
    """Under 12: every demo activity is older than that, so each slice existed at spin time."""
    accepted_by: int | None = None
    """Index into ``ctx.users``; ``None`` leaves the spin unaccepted."""
    hand_picked: int = 0
    """Spin over this many random ideas instead of the filtered pool."""


def _spins(ctx: DemoContext) -> list[DemoSpin]:
    """Oldest first. ``interested_by`` is what the app's "Only ideas I'm interested in" toggle
    sends (it starts on)."""
    users = ctx.users
    return [
        DemoSpin(0, WheelFilters(interested_by=users[0].id), hours_ago=11, accepted_by=0),
        DemoSpin(
            1,
            WheelFilters(category_id=ctx.categories["Movie night"].id),
            hours_ago=8,
            accepted_by=2,
        ),
        DemoSpin(2, WheelFilters(), hours_ago=5),  # the whole pool, sampled down to 50
        DemoSpin(0, WheelFilters(), hours_ago=2.5, hand_picked=4, accepted_by=1),
        DemoSpin(1, WheelFilters(interested_by=users[1].id, cost_max=20), hours_ago=0.5),
    ]


def create_spins(db: Session, ctx: DemoContext) -> None:
    ideas = [activity for activity in ctx.activities if activity.status is ActivityStatus.IDEA]
    for demo in _spins(ctx):
        activity_ids = (
            [activity.id for activity in ctx.rng.sample(ideas, demo.hand_picked)]
            if demo.hand_picked
            else None
        )
        spin = wheel_service.create_spin(
            db,
            ctx.access(ctx.users[demo.spinner]),
            SpinCreate(filters=demo.filters, activity_ids=activity_ids),
            rng=ctx.rng,
        )
        spin.created_at = ctx.now - timedelta(hours=demo.hours_ago)
        if demo.accepted_by is None:
            continue
        result = db.get_one(Activity, spin.result_activity_id)
        status_before = result.status
        wheel_service.accept(db, spin, ctx.memberships[ctx.users[demo.accepted_by].id])
        spin.accepted_at = spin.created_at + timedelta(minutes=ctx.rng.randint(1, 20))
        if result.status is not status_before:  # an idea moved to planning
            result.status_changed_at = result.updated_at = spin.accepted_at
