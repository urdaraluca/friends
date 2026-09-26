import 'package:friends/core/api/generated/export.dart';
import 'package:material_ui/material_ui.dart' show immutable;

/// Role checks (contract section 7.2). `$unknown` (a role a newer server
/// might add) is treated as the least privileged.
extension RoleChecks on Role {
  bool get isOwner => this == Role.owner;

  /// Admin or owner: "admin+" in the contract.
  bool get isAdminOrOwner => this == Role.owner || this == Role.admin;

  /// "Owner", "Admin" or "Member".
  String get label => switch (this) {
    Role.owner => 'Owner',
    Role.admin => 'Admin',
    Role.member || Role.$unknown => 'Member',
  };
}

/// What the signed-in user may do in a group, mirroring the authorization
/// matrix (contract section 7.2).
///
/// The UI uses it to hide actions; the server stays the authority (a 403
/// still comes back as `forbidden`). Invites carry their own `can_delete`
/// flag, which the UI prefers over [canRevoke].
@immutable
class GroupPermissions {
  const new({
    required this.myRole,
    required this.myUserId,
    required this.membersCanInvite,
  });

  final Role myRole;
  final String myUserId;

  /// The group's `members_can_invite` setting.
  final bool membersCanInvite;

  /// `PUT /groups/{id}`: admin+.
  bool get canEditGroup => myRole.isAdminOrOwner;

  /// `DELETE /groups/{id}`: owner.
  bool get canDeleteGroup => myRole.isOwner;

  /// Change roles and transfer ownership: owner.
  bool get canManageRoles => myRole.isOwner;

  /// Whether [member] is me.
  bool isMe(Member member) => member.user.id == myUserId;

  /// Make [member] an admin or a member: the owner, for anyone but
  /// themselves (the owner's own role only changes through a transfer).
  bool canChangeRoleOf(Member member) =>
      canManageRoles &&
      !isMe(member) &&
      (member.role == Role.admin || member.role == Role.member);

  /// Hand the group over to [member]: the owner, to anyone else.
  bool canTransferTo(Member member) => canManageRoles && !isMe(member);

  /// Remove [member] (not yourself: that is leaving). Admins remove
  /// members; the owner also removes admins; nobody removes the owner.
  bool canRemove(Member member) {
    if (isMe(member)) return false;
    return switch (member.role) {
      Role.member => myRole.isAdminOrOwner,
      Role.admin => myRole.isOwner,
      Role.owner || Role.$unknown => false,
    };
  }

  /// Anyone may leave; the owner only after a transfer (the server answers
  /// `409 owner_must_transfer`), unless they are the only member, which
  /// deletes the group.
  bool get canLeave => true;

  /// Create an invite: admin+, or anyone when `members_can_invite` is on.
  bool get canCreateInvite => myRole.isAdminOrOwner || membersCanInvite;

  /// Create an invite that never expires: admin+.
  bool get canCreateNeverExpiringInvite => myRole.isAdminOrOwner;

  /// See every invite of the group (members see their own).
  bool get seesAllInvites => myRole.isAdminOrOwner;

  /// Revoke [invite]: its creator, or admin+.
  bool canRevoke(Invite invite) =>
      myRole.isAdminOrOwner || invite.createdBy?.id == myUserId;

  @override
  bool operator ==(Object other) =>
      other is GroupPermissions &&
      other.myRole == myRole &&
      other.myUserId == myUserId &&
      other.membersCanInvite == membersCanInvite;

  @override
  int get hashCode => Object.hash(myRole, myUserId, membersCanInvite);
}
