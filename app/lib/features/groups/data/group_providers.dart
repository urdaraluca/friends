import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/features/groups/domain/group_permissions.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'group_providers.g.dart';

/// My groups, by name (`GET /groups`).
///
/// Kept alive: the groups list, the group switcher and the `/` redirect all
/// read it. It resets on logout and account switch (`currentUserId`), and
/// `GroupsController` invalidates it after every mutation that changes it.
@Riverpod(keepAlive: true)
Future<List<GroupSummary>> groups(Ref ref) {
  ref.watch(currentUserIdProvider);
  return apiCall(ref.watch(groupsClientProvider).listGroups);
}

/// One group with its settings (`GET /groups/{id}`). A 404 (not a member,
/// or deleted) is a `ProblemException`; see [isGroupNotFound].
@Riverpod(name: 'groupProvider')
Future<Group> groupDetails(Ref ref, String groupId) {
  ref.watch(currentUserIdProvider);
  final client = ref.watch(groupsClientProvider);
  return apiCall(() => client.getGroup(groupId: groupId));
}

/// A group's members: owner, then admins, then members, each by name.
@riverpod
Future<List<Member>> members(Ref ref, String groupId) {
  ref.watch(currentUserIdProvider);
  final client = ref.watch(groupsClientProvider);
  return apiCall(() => client.listMembers(groupId: groupId));
}

/// A group's invites, newest first. Admins see all of them, members only
/// their own (contract section 7.2).
@riverpod
Future<List<Invite>> invites(Ref ref, String groupId) {
  ref.watch(currentUserIdProvider);
  final client = ref.watch(invitesClientProvider);
  return apiCall(() => client.listInvites(groupId: groupId));
}

/// My role in a group, or null while the group loads (or failed to).
@riverpod
Role? myRole(Ref ref, String groupId) =>
    ref.watch(groupProvider(groupId)).value?.myRole;

/// What I may do in a group (contract section 7.2), or null while the group
/// loads. The UI hides what this forbids; the server stays the authority.
@riverpod
GroupPermissions? groupPermissions(Ref ref, String groupId) {
  final group = ref.watch(groupProvider(groupId)).value;
  final userId = ref.watch(currentUserIdProvider);
  if (group == null || userId == null) return null;
  return GroupPermissions(
    myRole: group.myRole,
    myUserId: userId,
    membersCanInvite: group.membersCanInvite,
  );
}

/// Whether [error] means the group can't be seen: a 404 from a group
/// endpoint (not a member, or deleted; contract section 7.1), or a group ID
/// in the path that isn't a UUID (422 on `path.group_id`, section 1.2).
bool isGroupNotFound(Object error) {
  final exception = ApiException.from(error);
  if (exception is! ProblemException) return false;
  if (exception.status == 404) return true;
  return exception.code == ErrorCodes.validationError &&
      exception.errors.any((e) => e.field == 'path.group_id');
}
