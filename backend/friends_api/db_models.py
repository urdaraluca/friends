"""Imports every feature's models so Base.metadata is complete (Alembic, tests).

Add one import per feature module that defines tables.
"""

from friends_api.core.db import Base

__all__ = ["Base"]
