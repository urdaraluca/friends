import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/features/groups/data/group_providers.dart';
import 'package:friends/features/groups/data/last_group_store.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'groups_controller.g.dart';

/// Every group, member and invite mutation (contract sections 8.4–8.5).
///
/// Each method throws `ApiException`s and, on success, invalidates the
/// providers whose data changed. A 403 or 404 also refreshes the group
/// (`groupProvider`): my role may have changed, or the group may be gone,
/// in which case `GroupShell` shows "Group not found".
@Riverpod(keepAlive: true)
class GroupsController extends _$GroupsController {
  @override
  void build() {}

  GroupsClient get _groups => ref.read(groupsClientProvider);

  InvitesClient get _invites => ref.read(invitesClientProvider);

  /// `POST /groups`. I become the owner.
  Future<Group> create(GroupCreate body) async {
    final group = await apiCall(() => _groups.createGroup(body: body));
    ref.invalidate(groupsProvider);
    return group;
  }

  /// `PUT /groups/{id}` with the complete new settings (admin+).
  Future<Group> updateGroup(String groupId, GroupUpdate body) async {
    final group = await _inGroup(
      groupId,
      () => _groups.updateGroup(groupId: groupId, body: body),
    );
    ref
      ..invalidate(groupsProvider)
      ..invalidate(groupProvider(groupId))
      ..invalidate(invitesProvider(groupId)); // members_can_invite
    return group;
  }

  /// `DELETE /groups/{id}` (owner). Navigate away from the group first.
  Future<void> deleteGroup(String groupId) async {
    await _inGroup(groupId, () => _groups.deleteGroup(groupId: groupId));
    await _left(groupId);
  }

  /// Leaves the group (`DELETE /groups/{id}/members/{me}`). The owner gets
  /// `409 owner_must_transfer` unless they are the only member, in which
  /// case the group is deleted. Navigate away from the group afterwards.
  Future<void> leave(String groupId) async {
    final me = ref.read(currentUserIdProvider);
    if (me == null) {
      throw const ProblemException(
        status: 401,
        code: ErrorCodes.unauthenticated,
      );
    }
    await _inGroup(
      groupId,
      () => _groups.removeMember(groupId: groupId, userId: me),
    );
    await _left(groupId);
  }

  /// `POST /groups/{id}/transfer-ownership`: [userId] becomes the owner and
  /// I become an admin.
  Future<Group> transferOwnership(String groupId, String userId) async {
    final group = await _inGroup(
      groupId,
      () => _groups.transferOwnership(
        groupId: groupId,
        body: TransferOwnership(userId: userId),
      ),
    );
    _refreshGroup(groupId);
    return group;
  }

  /// `PUT /groups/{id}/members/{user}/role` (owner).
  Future<Member> changeRole(
    String groupId,
    String userId,
    AssignableRole role,
  ) async {
    final member = await _inGroup(
      groupId,
      () => _groups.updateMemberRole(
        groupId: groupId,
        userId: userId,
        body: RoleUpdate(role: role),
      ),
    );
    ref
      ..invalidate(membersProvider(groupId))
      ..invalidate(invitesProvider(groupId));
    return member;
  }

  /// `DELETE /groups/{id}/members/{user}`: removes someone else.
  Future<void> removeMember(String groupId, String userId) async {
    await _inGroup(
      groupId,
      () => _groups.removeMember(groupId: groupId, userId: userId),
    );
    _refreshGroup(groupId);
  }

  /// `PUT /groups/{id}/members/me/settings`.
  Future<Member> updateMySettings(
    String groupId, {
    required bool showBirthday,
  }) async {
    final member = await _inGroup(
      groupId,
      () => _groups.updateMyMemberSettings(
        groupId: groupId,
        body: MemberSettingsUpdate(showBirthday: showBirthday),
      ),
    );
    ref.invalidate(membersProvider(groupId));
    return member;
  }

  /// `POST /groups/{id}/invites`.
  Future<Invite> createInvite(String groupId, InviteCreate body) async {
    final invite = await _inGroup(
      groupId,
      () => _invites.createInvite(groupId: groupId, body: body),
    );
    ref.invalidate(invitesProvider(groupId));
    return invite;
  }

  /// `DELETE /groups/{id}/invites/{invite}` (idempotent).
  Future<void> revokeInvite(String groupId, String inviteId) async {
    await _inGroup(
      groupId,
      () => _invites.revokeInvite(groupId: groupId, inviteId: inviteId),
    );
    ref.invalidate(invitesProvider(groupId));
  }

  /// `POST /invites/{code}/accept`: joins the group as a member (or
  /// changes nothing when I already am one). [code] must be normalized.
  Future<Group> acceptInvite(String code) async {
    final group = await apiCall(() => _invites.acceptInvite(code: code));
    ref
      ..invalidate(groupsProvider)
      ..invalidate(groupProvider(group.id))
      ..invalidate(membersProvider(group.id));
    return group;
  }

  /// Runs a call on [groupId]'s endpoints. On a 403 or 404 the group is
  /// reloaded: my role may have changed, or the group may be gone.
  Future<T> _inGroup<T>(String groupId, Future<T> Function() request) async {
    try {
      return await apiCall(request);
    } on ProblemException catch (e) {
      if (e.status == 403 || e.status == 404) _refreshGroup(groupId);
      rethrow;
    }
  }

  void _refreshGroup(String groupId) {
    ref
      ..invalidate(groupsProvider)
      ..invalidate(groupProvider(groupId))
      ..invalidate(membersProvider(groupId))
      ..invalidate(invitesProvider(groupId));
  }

  Future<void> _left(String groupId) async {
    ref.invalidate(groupsProvider);
    await ref.read(lastGroupStoreProvider).forget(groupId);
  }
}
