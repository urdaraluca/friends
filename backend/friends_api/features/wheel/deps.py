"""Wheel dependencies: the flat ``/wheel/spins/{spin_id}`` loader (contract section 7.1) and
the random number generator that picks the results."""

import random
import secrets
import uuid
from typing import Annotated

from fastapi import Depends

from friends_api.core.errors import NotFound
from friends_api.deps import CurrentUser, DbSession
from friends_api.features.wheel import service
from friends_api.features.wheel.service import SpinAccess


def load_spin(spin_id: uuid.UUID, db: DbSession, user: CurrentUser) -> SpinAccess:
    """The spin plus the caller's membership in its group. A missing spin and a non-member
    caller get the same 404."""
    access = service.get_access(db, spin_id, user.id)
    if access is None:
        raise NotFound("No such spin.")
    return access


SpinMember = Annotated[SpinAccess, Depends(load_spin)]

_SYSTEM_RNG = secrets.SystemRandom()


def get_wheel_rng() -> random.Random:
    """The OS's CSPRNG. Tests override this dependency (``app.dependency_overrides``) with a
    seeded ``random.Random``."""
    return _SYSTEM_RNG


WheelRng = Annotated[random.Random, Depends(get_wheel_rng)]
