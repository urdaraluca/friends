"""Imports every feature's models so Base.metadata is complete (Alembic, tests).

Add one import per feature module that defines tables.
"""

from friends_api.core.db import Base
from friends_api.features.auth import models as auth_models
from friends_api.features.group_log import models as group_log_models
from friends_api.features.groups import models as groups_models
from friends_api.features.invites import models as invites_models

__all__ = ["Base", "auth_models", "group_log_models", "groups_models", "invites_models"]
