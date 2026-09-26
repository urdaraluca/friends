"""Imports every feature's models so Base.metadata is complete (Alembic, tests).

Add one import per feature module that defines tables.
"""

from friends_api.core.db import Base
from friends_api.features.activities import models as activities_models
from friends_api.features.auth import models as auth_models
from friends_api.features.categories import models as categories_models
from friends_api.features.group_log import models as group_log_models
from friends_api.features.groups import models as groups_models
from friends_api.features.invites import models as invites_models
from friends_api.features.polls import models as polls_models
from friends_api.features.wheel import models as wheel_models

__all__ = [
    "Base",
    "activities_models",
    "auth_models",
    "categories_models",
    "group_log_models",
    "groups_models",
    "invites_models",
    "polls_models",
    "wheel_models",
]
