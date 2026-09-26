"""The fixed setup of a demo run: the users and the group every step builds on."""

import random
from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from friends_api.core.db import utcnow
from friends_api.demo.context import (
    DEMO_EMAILS,
    DEMO_NAMES,
    DEMO_PASSWORD,
    DEMO_TIMEZONE,
    DemoContext,
)
from friends_api.features.auth import service as auth_service
from friends_api.features.auth.models import User
from friends_api.features.auth.service import AuthContext
from friends_api.features.categories.models import Category
from friends_api.features.group_log.service import log_event
from friends_api.features.groups import service as groups_service
from friends_api.features.groups.models import Role
from friends_api.features.groups.schemas import GroupCreate
from friends_api.features.invites import service as invites_service
from friends_api.features.invites.models import Invite


def demo_users_exist(db: Session) -> bool:
    return db.scalar(select(User.id).where(User.email.in_(DEMO_EMAILS)).limit(1)) is not None


def create_base(
    db: Session, auth: AuthContext, *, now: datetime, rng: random.Random
) -> DemoContext:
    """3 users, and one group with the default categories: demo1 owns it, demo2 is an admin
    and demo3 a member (both joined through an invite)."""
    users = [
        auth_service.create_user(
            db,
            auth,
            email=email,
            password=DEMO_PASSWORD,
            display_name=name,
            timezone=DEMO_TIMEZONE,
        )
        for email, name in zip(DEMO_EMAILS, DEMO_NAMES, strict=True)
    ]
    owner = users[0]
    access = groups_service.create_group(
        db,
        owner,
        GroupCreate(
            name="Demo friends",
            description="Seeded by `python -m friends_api.cli seed-demo`.",
            emoji="🎲",
            color="#7E57C2",
            currency="EUR",
            timezone=DEMO_TIMEZONE,
        ),
    )
    group = access.group

    # The real clock, not ctx.now: joining checks the invite against the current time, and a
    # run may use a fixed ``now`` in the past (tests do).
    expires_at = utcnow() + timedelta(days=7)
    invite = Invite(
        group_id=group.id,
        code="".join(rng.choice(invites_service.ALPHABET) for _ in range(10)),
        created_by_id=owner.id,
        expires_at=expires_at,
        max_uses=len(users) - 1,
    )
    db.add(invite)
    db.flush()
    log_event(
        db,
        group_id=group.id,
        actor_id=owner.id,
        action="invite.created",
        subject_type="invite",
        subject_id=invite.id,
        data={"max_uses": invite.max_uses, "expires_at": expires_at.isoformat()},
    )
    memberships = {owner.id: access.membership}
    for user in users[1:]:
        joined = invites_service.join_with_invite(db, user, invite, via="invite")
        memberships[user.id] = joined.membership

    admin = memberships[users[1].id]
    admin.role = Role.ADMIN
    log_event(
        db,
        group_id=group.id,
        actor_id=owner.id,
        action="member.role_changed",
        subject_type="member",
        subject_id=admin.user_id,
        data={"from": Role.MEMBER.value, "to": Role.ADMIN.value},
    )
    db.flush()
    categories = db.scalars(select(Category).where(Category.group_id == group.id))
    return DemoContext(
        now=now,
        rng=rng,
        users=users,
        group=group,
        memberships=memberships,
        categories={category.name: category for category in categories},
    )
