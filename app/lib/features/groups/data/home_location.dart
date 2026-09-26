import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/groups/data/group_providers.dart';
import 'package:friends/features/groups/data/last_group_store.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

/// Where `/` sends a signed-in user: the last opened group's backlog while
/// that group is still in [groups], else the groups list.
String homeLocationFor({
  required String? lastGroupId,
  required List<GroupSummary> groups,
}) {
  if (lastGroupId != null && groups.any((g) => g.id == lastGroupId)) {
    return Routes.groupBacklog(lastGroupId);
  }
  return Routes.groups;
}

/// [homeLocationFor] with the stored last group and my groups. Any failure
/// (offline, storage) goes to the groups list, which explains the error and
/// offers Retry.
///
/// This runs inside a go_router redirect, and go_router turns *any* error
/// reported in the redirect's zone into its error page. So it must not
/// create `groupsProvider` here: a failing provider built in this zone reports
/// its error to the zone even when the awaited `.future` is caught. An
/// existing list is reused; otherwise it is one plain request.
Future<String> resolveHomeLocation(Ref ref) async {
  try {
    final lastGroupId = await ref.read(lastGroupStoreProvider).read();
    if (lastGroupId == null) return Routes.groups;
    final cached = ref.exists(groupsProvider)
        ? ref.read(groupsProvider).value
        : null;
    final groups =
        cached ??
        await apiCall<List<GroupSummary>>(
          ref.read(groupsClientProvider).listGroups,
        );
    return homeLocationFor(lastGroupId: lastGroupId, groups: groups);
  } on Object {
    return Routes.groups;
  }
}
