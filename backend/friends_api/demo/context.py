import random
import uuid
from dataclasses import dataclass, field
from datetime import datetime

from friends_api.features.activities.models import Activity
from friends_api.features.auth.models import User
from friends_api.features.categories.models import Category
from friends_api.features.groups.models import Group, Membership
from friends_api.features.groups.service import GroupAccess

DEMO_EMAILS = ("demo1@example.com", "demo2@example.com", "demo3@example.com")
DEMO_NAMES = ("Ana", "Bogdan", "Carla")
DEMO_PASSWORD = "friends-demo-password"  # noqa: S105 - printed on purpose; dev data only
DEMO_TIMEZONE = "Europe/Bucharest"
DEMO_SEED = 20261001


@dataclass
class DemoContext:
    """What a seed-demo run has created so far. Steps read it and add their own rows."""

    now: datetime
    """One instant for the whole run: steps place their data relative to it."""
    rng: random.Random
    """Seeded, so the same code produces the same data."""
    users: list[User]
    """demo1 (owner), demo2 (admin), demo3 (member)."""
    group: Group
    memberships: dict[uuid.UUID, Membership]
    """By user ID."""
    categories: dict[str, Category]
    """By name, subcategories included (names are unique across the demo group)."""
    activities: list[Activity] = field(default_factory=list)

    def access(self, user: User) -> GroupAccess:
        """``user``'s access to the demo group, for calling services as that user."""
        return GroupAccess(group=self.group, membership=self.memberships[user.id])
