"""Category permissions (contract section 7.2); they also compute the ``can_*`` flags.

Any member may create a category.
"""

from friends_api.features.categories.models import Category
from friends_api.features.groups.models import Membership


def can_edit_category(actor: Membership, category: Category) -> bool:
    """Edit, including ``field_defs``: the creator or an admin+."""
    return actor.is_admin or category.created_by_id == actor.user_id


def can_delete_category(actor: Membership, category: Category) -> bool:
    return can_edit_category(actor, category)
