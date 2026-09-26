"""Polls inside activities (contract sections 3.1, 7.2-7.5 and 8.9).

A poll is open while ``closed_at`` is null and ``closes_at`` is null or still in the future. That
is computed on read (``Poll.is_open``); nothing closes a poll in the background.
"""

import string
import uuid
from collections import defaultdict
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from sqlalchemy import delete, exists, func, select
from sqlalchemy.orm import Session

from friends_api.core.db import utcnow
from friends_api.core.errors import Conflict, FieldError, Forbidden, Unprocessable
from friends_api.features.activities.models import Activity
from friends_api.features.activities.service import ActivityAccess
from friends_api.features.group_log.service import log_event
from friends_api.features.groups import service as groups_service
from friends_api.features.groups.models import Membership
from friends_api.features.groups.service import limit_reached
from friends_api.features.polls import policies
from friends_api.features.polls.models import (
    MAX_OPTIONS,
    MAX_POLLS_PER_ACTIVITY,
    MIN_OPTIONS,
    Poll,
    PollOption,
    PollVote,
)
from friends_api.features.polls.schemas import Poll as PollOut
from friends_api.features.polls.schemas import PollCreate, PollOptionCreate, PollUpdate
from friends_api.features.polls.schemas import PollOption as PollOptionOut
from friends_api.features.users.lookup import public_user, users_by_id


@dataclass(frozen=True, slots=True)
class PollAccess:
    """A poll, its activity and the caller's membership in their group."""

    poll: Poll
    activity: Activity
    membership: Membership


@dataclass(frozen=True, slots=True)
class PollOptionAccess:
    """An option of a poll the caller can see."""

    access: PollAccess
    option: PollOption


def get_access(db: Session, poll_id: uuid.UUID, user_id: uuid.UUID) -> PollAccess | None:
    row = db.execute(
        select(Poll, Activity, Membership)
        .join(Activity, Activity.id == Poll.activity_id)
        .join(Membership, Membership.group_id == Poll.group_id)
        .where(Poll.id == poll_id, Membership.user_id == user_id)
    ).first()
    return PollAccess(poll=row[0], activity=row[1], membership=row[2]) if row else None


def get_option_access(
    db: Session, poll_id: uuid.UUID, option_id: uuid.UUID, user_id: uuid.UUID
) -> PollOptionAccess | None:
    row = db.execute(
        select(PollOption, Poll, Activity, Membership)
        .join(Poll, Poll.id == PollOption.poll_id)
        .join(Activity, Activity.id == Poll.activity_id)
        .join(Membership, Membership.group_id == Poll.group_id)
        .where(PollOption.id == option_id, Poll.id == poll_id, Membership.user_id == user_id)
    ).first()
    if row is None:
        return None
    return PollOptionAccess(
        access=PollAccess(poll=row[1], activity=row[2], membership=row[3]), option=row[0]
    )


# --- reading ------------------------------------------------------------------------------


def build_polls(
    db: Session,
    activity: Activity,
    actor: Membership,
    polls: Sequence[Poll],
    *,
    now: datetime | None = None,
) -> list[PollOut]:
    """Responses for polls of one activity, with three queries however many polls and options
    there are (options, votes, users)."""
    if not polls:
        return []
    now = now or utcnow()
    poll_ids = [poll.id for poll in polls]
    options: defaultdict[uuid.UUID, list[PollOption]] = defaultdict(list)
    for option in db.scalars(
        select(PollOption)
        .where(PollOption.poll_id.in_(poll_ids))
        .order_by(PollOption.position, PollOption.id)
    ):
        options[option.poll_id].append(option)
    voters: defaultdict[uuid.UUID, list[uuid.UUID]] = defaultdict(list)  # by option
    poll_voters: defaultdict[uuid.UUID, set[uuid.UUID]] = defaultdict(set)
    for poll_id, option_id, user_id in db.execute(
        select(PollVote.poll_id, PollVote.option_id, PollVote.user_id)
        .where(PollVote.poll_id.in_(poll_ids))
        .order_by(PollVote.created_at, PollVote.user_id)
    ).tuples():
        voters[option_id].append(user_id)
        poll_voters[poll_id].add(user_id)
    users = users_by_id(
        db,
        [
            *(poll.created_by_id for poll in polls),
            *(option.added_by_id for group in options.values() for option in group),
            *(user_id for group in poll_voters.values() for user_id in group),
        ],
    )

    result: list[PollOut] = []
    for poll in polls:
        option_rows = [
            PollOptionOut(
                id=option.id,
                label=option.label,
                url=option.url,
                position=option.position,
                vote_count=len(voters[option.id]),
                voters=[
                    user
                    for user_id in voters[option.id]
                    if (user := public_user(users, user_id)) is not None
                ],
                added_by=public_user(users, option.added_by_id),
                can_delete=policies.can_delete_poll_option(
                    actor, poll, activity, option, has_votes=bool(voters[option.id])
                ),
            )
            for option in options[poll.id]
        ]
        top = max((option.vote_count for option in option_rows), default=0)
        result.append(
            PollOut(
                id=poll.id,
                group_id=poll.group_id,
                activity_id=poll.activity_id,
                question=poll.question,
                allow_multiple=poll.allow_multiple,
                closes_at=poll.closes_at,
                closed_at=poll.closed_at,
                is_open=poll.is_open(now),
                options=option_rows,
                my_option_ids=[
                    option.id for option in options[poll.id] if actor.user_id in voters[option.id]
                ],
                total_voters=len(poll_voters[poll.id]),
                winning_option_ids=[
                    option.id for option in option_rows if top > 0 and option.vote_count == top
                ],
                created_by=public_user(users, poll.created_by_id),
                can_manage=policies.can_manage_poll(actor, poll, activity),
                created_at=poll.created_at,
                updated_at=poll.updated_at,
            )
        )
    return result


def to_poll(db: Session, access: PollAccess) -> PollOut:
    return build_polls(db, access.activity, access.membership, [access.poll])[0]


def list_polls(db: Session, access: ActivityAccess) -> list[PollOut]:
    """The activity's polls, oldest first."""
    polls = db.scalars(
        select(Poll)
        .where(Poll.activity_id == access.activity.id)
        .order_by(Poll.created_at, Poll.id)
    ).all()
    return build_polls(db, access.activity, access.membership, polls)


# --- validation ---------------------------------------------------------------------------


def _closes_at_in_the_past() -> Unprocessable:
    message = "The closing time must be in the future."
    return Unprocessable(
        message, errors=[FieldError(field="closes_at", message=message, type="datetime_future")]
    )


_ASCII_LOWER = str.maketrans(string.ascii_uppercase, string.ascii_lowercase)


def _nocase(label: str) -> str:
    """Folds a label the way SQLite's ``COLLATE NOCASE`` does: ASCII letters only (contract
    1.10), so 'Maße' and 'Masse' stay different, as the unique index sees them."""
    return label.translate(_ASCII_LOWER)


def _check_unique_labels(options: Sequence[PollOptionCreate]) -> None:
    seen: set[str] = set()
    errors: list[FieldError] = []
    for i, option in enumerate(options):
        folded = _nocase(option.label)
        if folded in seen:
            errors.append(
                FieldError(
                    field=f"options.{i}.label",
                    message="This option is already in the poll.",
                    type="value_error",
                )
            )
        seen.add(folded)
    if errors:
        raise Unprocessable("Option labels must be unique.", errors=errors)


def _ensure_manager(access: PollAccess) -> None:
    if not policies.can_manage_poll(access.membership, access.poll, access.activity):
        raise Forbidden("Only the poll's creator, the activity's owner or an admin can do this.")


def _ensure_open(poll: Poll, now: datetime) -> None:
    if not poll.is_open(now):
        raise Conflict("This poll is closed.", code="poll_closed")


def _log(db: Session, poll: Poll, actor_id: uuid.UUID | None, action: str, **data: Any) -> None:
    """A ``poll.*`` row (contract section 3.2). Without ``data``, the poll's activity and
    question."""
    log_event(
        db,
        group_id=poll.group_id,
        actor_id=actor_id,
        action=action,
        subject_type="poll",
        subject_id=poll.id,
        data=data or {"activity_id": str(poll.activity_id), "question": poll.question},
    )


# --- writing ------------------------------------------------------------------------------


def create_poll(
    db: Session, access: ActivityAccess, body: PollCreate, *, now: datetime | None = None
) -> Poll:
    """Any member. The options keep the body's order and count as added by the creator.
    Flushes; the caller commits."""
    activity, actor = access.activity, access.membership
    now = now or utcnow()
    count = db.scalar(select(func.count()).where(Poll.activity_id == activity.id)) or 0
    if count >= MAX_POLLS_PER_ACTIVITY:
        raise limit_reached(f"An activity can have at most {MAX_POLLS_PER_ACTIVITY} polls.")
    _check_unique_labels(body.options)
    if body.closes_at is not None and body.closes_at <= now:
        raise _closes_at_in_the_past()
    poll = Poll(
        group_id=activity.group_id,
        activity_id=activity.id,
        question=body.question,
        allow_multiple=body.allow_multiple,
        closes_at=body.closes_at,
        created_by_id=actor.user_id,
        created_at=now,
        updated_at=now,
    )
    db.add(poll)
    db.flush()
    db.add_all(
        PollOption(
            poll_id=poll.id,
            label=option.label,
            url=option.url,
            position=position,
            added_by_id=actor.user_id,
            created_at=now,
        )
        for position, option in enumerate(body.options)
    )
    _log(db, poll, actor.user_id, "poll.created")
    db.flush()
    return poll


def update_poll(db: Session, access: PollAccess, body: PollUpdate) -> None:
    """The manager; last write wins. ``closes_at`` must be in the future unless it is the
    stored value sent back unchanged."""
    _ensure_manager(access)
    poll = access.poll
    if (
        body.closes_at is not None
        and body.closes_at != poll.closes_at
        and body.closes_at <= utcnow()
    ):
        raise _closes_at_in_the_past()
    if (body.question, body.closes_at) != (poll.question, poll.closes_at):
        poll.question = body.question
        poll.closes_at = body.closes_at
        _log(db, poll, access.membership.user_id, "poll.updated")
    db.commit()


def delete_poll(db: Session, access: PollAccess) -> None:
    """The manager. Options and votes go with it (``ON DELETE CASCADE``)."""
    _ensure_manager(access)
    _log(db, access.poll, access.membership.user_id, "poll.deleted")
    db.delete(access.poll)
    db.commit()


def close(db: Session, poll: Poll, *, actor_id: uuid.UUID | None, now: datetime) -> bool:
    """Sets ``closed_at``; closing a closed poll changes nothing. Flushes; the caller
    commits."""
    if poll.closed_at is not None:
        return False
    poll.closed_at = now
    _log(db, poll, actor_id, "poll.closed")
    db.flush()
    return True


def close_poll(db: Session, access: PollAccess) -> None:
    """The manager (idempotent)."""
    _ensure_manager(access)
    close(db, access.poll, actor_id=access.membership.user_id, now=utcnow())
    db.commit()


def reopen_poll(db: Session, access: PollAccess) -> None:
    """The manager: clears ``closed_at``, and ``closes_at`` too once it has passed. An open poll
    stays as it is."""
    _ensure_manager(access)
    poll, now = access.poll, utcnow()
    if not poll.is_open(now):
        poll.closed_at = None
        if poll.closes_at is not None and poll.closes_at <= now:
            poll.closes_at = None
        _log(db, poll, access.membership.user_id, "poll.reopened")
    db.commit()


def insert_option(
    db: Session,
    poll: Poll,
    user_id: uuid.UUID,
    body: PollOptionCreate,
    *,
    now: datetime | None = None,
) -> PollOption:
    """Any member, while the poll is open; the option goes last. Flushes; the caller
    commits."""
    now = now or utcnow()
    _ensure_open(poll, now)
    existing = db.execute(
        select(PollOption.label, PollOption.position).where(PollOption.poll_id == poll.id)
    ).all()
    if len(existing) >= MAX_OPTIONS:
        raise limit_reached(f"A poll can have at most {MAX_OPTIONS} options.")
    folded = _nocase(body.label)
    if any(_nocase(label) == folded for label, _ in existing):
        raise Conflict("This option is already in the poll.", code="name_taken")
    option = PollOption(
        poll_id=poll.id,
        label=body.label,
        url=body.url,
        position=max((position for _, position in existing), default=-1) + 1,
        added_by_id=user_id,
        created_at=now,
    )
    db.add(option)
    db.flush()
    _log(db, poll, user_id, "poll.option_added", option_id=str(option.id), label=option.label)
    db.flush()
    return option


def add_poll_option(db: Session, access: PollAccess, body: PollOptionCreate) -> None:
    insert_option(db, access.poll, access.membership.user_id, body)
    db.commit()


def delete_poll_option(db: Session, target: PollOptionAccess) -> None:
    """Whoever added the option while it has no votes, or the manager. Its votes go with it
    (``ON DELETE CASCADE``); a poll keeps at least 2 options."""
    access, option = target.access, target.option
    has_votes = bool(db.scalar(select(exists().where(PollVote.option_id == option.id))))
    if not policies.can_delete_poll_option(
        access.membership, access.poll, access.activity, option, has_votes=has_votes
    ):
        raise Forbidden(
            "Only the poll's manager can delete an option that has votes."
            if option.added_by_id == access.membership.user_id
            else "Only whoever added this option or the poll's manager can delete it."
        )
    count = db.scalar(select(func.count()).where(PollOption.poll_id == option.poll_id)) or 0
    if count <= MIN_OPTIONS:
        raise limit_reached(f"A poll needs at least {MIN_OPTIONS} options.")
    _log(
        db,
        access.poll,
        access.membership.user_id,
        "poll.option_deleted",
        option_id=str(option.id),
        label=option.label,
    )
    db.delete(option)
    db.commit()


def replace_votes(
    db: Session,
    poll: Poll,
    user_id: uuid.UUID,
    option_ids: Sequence[uuid.UUID],
    *,
    now: datetime | None = None,
) -> bool:
    """Makes ``option_ids`` the member's whole vote on an open poll (empty retracts it;
    duplicates are ignored). Votes that stay keep their time. Returns whether anything changed.
    Flushes; the caller commits."""
    now = now or utcnow()
    _ensure_open(poll, now)
    wanted = list(dict.fromkeys(option_ids))
    valid = set(db.scalars(select(PollOption.id).where(PollOption.poll_id == poll.id)))
    errors = [
        FieldError(
            field=f"option_ids.{list(option_ids).index(option_id)}",
            message="No such option in this poll.",
            type="invalid_reference",
        )
        for option_id in wanted
        if option_id not in valid
    ]
    if errors:
        raise Unprocessable("No such option in this poll.", code="invalid_reference", errors=errors)
    if not poll.allow_multiple and len(wanted) > 1:
        message = "This poll allows only one choice."
        raise Unprocessable(
            message,
            code="too_many_choices",
            errors=[FieldError(field="option_ids", message=message, type="too_many_choices")],
        )
    current = set(
        db.scalars(
            select(PollVote.option_id).where(
                PollVote.poll_id == poll.id, PollVote.user_id == user_id
            )
        )
    )
    if current == set(wanted):
        return False
    db.execute(
        delete(PollVote).where(
            PollVote.poll_id == poll.id,
            PollVote.user_id == user_id,
            PollVote.option_id.not_in(wanted),
        )
    )
    db.add_all(
        PollVote(option_id=option_id, user_id=user_id, poll_id=poll.id, created_at=now)
        for option_id in wanted
        if option_id not in current
    )
    _log(db, poll, user_id, "poll.voted", option_ids=[str(option_id) for option_id in wanted])
    db.flush()
    return True


def set_my_vote(db: Session, access: PollAccess, option_ids: Sequence[uuid.UUID]) -> None:
    replace_votes(db, access.poll, access.membership.user_id, option_ids)
    db.commit()


# --- reactions to other features ----------------------------------------------------------


def _on_membership_end(db: Session, group_id: uuid.UUID, user_id: uuid.UUID) -> None:
    """Contract section 7.5: the leaver's votes on this group's polls go."""
    db.execute(
        delete(PollVote).where(
            PollVote.user_id == user_id,
            PollVote.poll_id.in_(select(Poll.id).where(Poll.group_id == group_id)),
        )
    )


groups_service.MEMBERSHIP_END_CLEANUPS.append(_on_membership_end)
