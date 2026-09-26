from fastapi import APIRouter, status

from friends_api.deps import DbSession
from friends_api.features.activities.deps import ActivityMember
from friends_api.features.polls import service
from friends_api.features.polls.deps import PollMember, PollOptionMember
from friends_api.features.polls.schemas import (
    Poll,
    PollCreate,
    PollOptionCreate,
    PollUpdate,
    VoteRequest,
)
from friends_api.features.polls.service import PollAccess

router = APIRouter(tags=["polls"])


@router.get("/activities/{activity_id}/polls")
def list_polls(db: DbSession, access: ActivityMember) -> list[Poll]:
    """Oldest first."""
    return service.list_polls(db, access)


@router.post("/activities/{activity_id}/polls", status_code=status.HTTP_201_CREATED)
def create_poll(body: PollCreate, db: DbSession, access: ActivityMember) -> Poll:
    """Any member; at most 10 polls per activity. ``closes_at`` must be in the future."""
    poll = service.create_poll(db, access, body)
    db.commit()
    return service.to_poll(
        db, PollAccess(poll=poll, activity=access.activity, membership=access.membership)
    )


@router.get("/polls/{poll_id}")
def get_poll(db: DbSession, access: PollMember) -> Poll:
    return service.to_poll(db, access)


@router.put("/polls/{poll_id}")
def update_poll(body: PollUpdate, db: DbSession, access: PollMember) -> Poll:
    """The poll's manager (its creator, the activity's owner or an admin). ``closes_at`` must be
    in the future, or the stored value sent back unchanged."""
    service.update_poll(db, access, body)
    return service.to_poll(db, access)


@router.delete("/polls/{poll_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_poll(db: DbSession, access: PollMember) -> None:
    """The poll's manager."""
    service.delete_poll(db, access)


@router.post("/polls/{poll_id}/close")
def close_poll(db: DbSession, access: PollMember) -> Poll:
    """The poll's manager. Closing a closed poll changes nothing."""
    service.close_poll(db, access)
    return service.to_poll(db, access)


@router.post("/polls/{poll_id}/reopen")
def reopen_poll(db: DbSession, access: PollMember) -> Poll:
    """The poll's manager. Also clears a ``closes_at`` that has passed."""
    service.reopen_poll(db, access)
    return service.to_poll(db, access)


@router.post("/polls/{poll_id}/options", status_code=status.HTTP_201_CREATED)
def add_poll_option(body: PollOptionCreate, db: DbSession, access: PollMember) -> Poll:
    """Any member, while the poll is open; the option goes last."""
    service.add_poll_option(db, access, body)
    return service.to_poll(db, access)


@router.delete("/polls/{poll_id}/options/{option_id}")
def delete_poll_option(db: DbSession, target: PollOptionMember) -> Poll:
    """Whoever added the option (while it has no votes) or the poll's manager. Its votes are
    removed; a poll keeps at least 2 options."""
    service.delete_poll_option(db, target)
    return service.to_poll(db, target.access)


@router.put("/polls/{poll_id}/votes/me")
def set_my_vote(body: VoteRequest, db: DbSession, access: PollMember) -> Poll:
    """Replaces the caller's whole vote; an empty list retracts it and duplicate IDs are
    ignored. At most one option on a single-choice poll."""
    service.set_my_vote(db, access, body.option_ids)
    return service.to_poll(db, access)
