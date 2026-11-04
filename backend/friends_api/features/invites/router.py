import uuid

from fastapi import APIRouter, BackgroundTasks, Depends, Request, status

from friends_api.core.mail import send_safely
from friends_api.core.ratelimit import limit_by_ip, limit_by_user
from friends_api.deps import AppSettings, CurrentUser, DbSession, GroupMember, MailerDep
from friends_api.features.groups import policies
from friends_api.features.groups import service as groups_service
from friends_api.features.groups.schemas import Group
from friends_api.features.invites import service
from friends_api.features.invites.schemas import Invite, InviteCreate, InviteEmail, InvitePreview

router = APIRouter(tags=["invites"])


@router.get("/groups/{group_id}/invites")
def list_invites(db: DbSession, settings: AppSettings, access: GroupMember) -> list[Invite]:
    """Newest first (at most 100). Admins see every invite, members only their own."""
    return [
        service.to_invite(db, settings, invite, access.membership)
        for invite in service.list_invites(db, access)
        if policies.can_see_invite(access.membership, invite)
    ]


@router.post("/groups/{group_id}/invites", status_code=status.HTTP_201_CREATED)
def create_invite(
    body: InviteCreate, db: DbSession, settings: AppSettings, access: GroupMember
) -> Invite:
    invite = service.create_invite(db, access, body)
    return service.to_invite(db, settings, invite, access.membership)


@router.delete("/groups/{group_id}/invites/{invite_id}", status_code=status.HTTP_204_NO_CONTENT)
def revoke_invite(invite_id: uuid.UUID, db: DbSession, access: GroupMember) -> None:
    """Idempotent."""
    service.revoke_invite(db, access, service.get_group_invite(db, access, invite_id))


@router.post("/groups/{group_id}/invites/{invite_id}/email", status_code=status.HTTP_202_ACCEPTED)
def email_invite(
    invite_id: uuid.UUID,
    body: InviteEmail,
    db: DbSession,
    settings: AppSettings,
    access: GroupMember,
    user: CurrentUser,
    mailer: MailerDep,
    background: BackgroundTasks,
    request: Request,
) -> None:
    """Emails the invite's link to ``email``. Whoever can see the invite, with a verified email
    of their own; at most 10 an hour."""
    limit_by_user(request, "invite_email", user.id)
    invite = service.get_group_invite(db, access, invite_id)
    email = service.invite_email(db, settings, access, user, invite, body.email)
    background.add_task(send_safely, mailer, email)


@router.get("/invites/{code}", dependencies=[Depends(limit_by_ip("invites"))])
def preview_invite(code: str, db: DbSession) -> InvitePreview:
    """Public: shows which group an invite is for and whether it can still be used."""
    return service.preview(db, service.find_by_code(db, code))


@router.post("/invites/{code}/accept", dependencies=[Depends(limit_by_ip("invites"))])
def accept_invite(code: str, db: DbSession, user: CurrentUser) -> Group:
    """Joins the group as a member. Accepting again when already a member changes nothing."""
    access = service.join_with_invite(db, user, service.find_by_code(db, code), via="invite")
    db.commit()
    return groups_service.to_group(db, access.group, access.membership)
