"""Wheel permissions (contract section 7.2).

Any member may spin the wheel and accept a spin, whoever spun it. ``WheelSpin`` has no
``can_*`` flags, so these only enforce.
"""

from friends_api.features.groups.models import Membership
from friends_api.features.wheel.models import WheelSpin


def can_spin(actor: Membership) -> bool:
    return True


def can_accept_spin(actor: Membership, spin: WheelSpin) -> bool:
    return True
