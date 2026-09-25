"""Imports every feature's models so Base.metadata is complete (Alembic, tests).

Add one import per feature module that defines tables.
"""

from friends_api.core.db import Base
from friends_api.features.auth import models as auth_models

__all__ = ["Base", "auth_models"]
