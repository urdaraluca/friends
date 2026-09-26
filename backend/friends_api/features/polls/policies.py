"""Poll permissions (contract section 7.2); they also compute the ``can_*`` flags.

Any member may create a poll, add an option and vote. The "manager" of a poll is its creator,
the owner of its activity, or an admin+.
"""

from friends_api.features.activities.models import Activity
from friends_api.features.groups.models import Membership
from friends_api.features.polls.models import Poll, PollOption


def can_manage_poll(actor: Membership, poll: Poll, activity: Activity) -> bool:
    """Edit, close, reopen or delete the poll."""
    return actor.is_admin or actor.user_id in (poll.created_by_id, activity.owner_id)


def can_delete_poll_option(
    actor: Membership, poll: Poll, activity: Activity, option: PollOption, *, has_votes: bool
) -> bool:
    """Whoever added the option, while nobody has voted for it; the manager at any time."""
    if can_manage_poll(actor, poll, activity):
        return True
    return option.added_by_id == actor.user_id and not has_votes
