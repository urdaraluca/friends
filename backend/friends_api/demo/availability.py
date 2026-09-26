"""Demo availability: three weeks of answers for each demo user, so the group heatmap has
best days to show. Weekends lean free, weekday evenings more often than daytimes."""

from datetime import timedelta
from zoneinfo import ZoneInfo

from sqlalchemy.orm import Session

from friends_api.demo.context import DEMO_TIMEZONE, DemoContext
from friends_api.features.availability.models import (
    Availability,
    AvailabilitySlot,
    AvailabilityStatus,
)

DAYS = 21


def create_availability(db: Session, ctx: DemoContext) -> None:
    today = ctx.now.astimezone(ZoneInfo(DEMO_TIMEZONE)).date()
    statuses = list(AvailabilityStatus)
    for user in ctx.users:
        for offset in range(DAYS):
            day = today + timedelta(days=offset)
            if ctx.rng.random() < 0.25:
                continue  # not answered
            weekend = day.weekday() >= 5
            if weekend:
                status = ctx.rng.choices(statuses, weights=(6, 3, 1))[0]
                db.add(
                    Availability(
                        user_id=user.id, date=day, slot=AvailabilitySlot.ALL_DAY, status=status
                    )
                )
            else:
                evening = ctx.rng.choices(statuses, weights=(5, 3, 2))[0]
                daytime = ctx.rng.choices(statuses, weights=(1, 2, 7))[0]
                db.add_all(
                    [
                        Availability(
                            user_id=user.id,
                            date=day,
                            slot=AvailabilitySlot.EVENING,
                            status=evening,
                        ),
                        Availability(
                            user_id=user.id,
                            date=day,
                            slot=AvailabilitySlot.MORNING,
                            status=daytime,
                        ),
                        Availability(
                            user_id=user.id,
                            date=day,
                            slot=AvailabilitySlot.AFTERNOON,
                            status=daytime,
                        ),
                    ]
                )
