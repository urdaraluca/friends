"""When each person is free (contract section 13).

Availability is per user, not per group: one answer shows in every group the user belongs to,
so nobody is asked the same thing in each group.
"""

import uuid
from datetime import date
from enum import StrEnum

from sqlalchemy import ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from friends_api.core.db import Base, IdMixin, TimestampMixin, str_enum


class AvailabilitySlot(StrEnum):
    ALL_DAY = "all_day"
    MORNING = "morning"
    AFTERNOON = "afternoon"
    EVENING = "evening"


PARTS_OF_DAY = (AvailabilitySlot.MORNING, AvailabilitySlot.AFTERNOON, AvailabilitySlot.EVENING)


class AvailabilityStatus(StrEnum):
    FREE = "free"
    MAYBE = "maybe"
    BUSY = "busy"


class Availability(IdMixin, TimestampMixin, Base):
    """A user's answer for one date and slot."""

    __tablename__ = "availability"
    __table_args__ = (UniqueConstraint("user_id", "date", "slot"),)

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    date: Mapped[date]
    slot: Mapped[AvailabilitySlot] = mapped_column(str_enum(AvailabilitySlot, 10))
    status: Mapped[AvailabilityStatus] = mapped_column(str_enum(AvailabilityStatus, 5))
