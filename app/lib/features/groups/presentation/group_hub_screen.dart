import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/core/widgets/confirm_dialog.dart';
import 'package:friends/features/groups/data/group_providers.dart';
import 'package:friends/features/groups/data/groups_controller.dart';
import 'package:friends/features/groups/domain/group_permissions.dart';
import 'package:friends/features/groups/presentation/widgets/group_action.dart';
import 'package:friends/features/groups/presentation/widgets/group_avatar.dart';
import 'package:friends/features/groups/presentation/widgets/group_not_found_view.dart';
import 'package:friends/features/groups/presentation/widgets/invites_section.dart';
import 'package:friends/features/groups/presentation/widgets/members_section.dart';
import 'package:friends/features/groups/presentation/widgets/transfer_ownership_dialog.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// The group's "Group" tab (`/groups/:groupId/group`): members and roles,
/// my settings, invites, and edit / leave / delete.
class GroupHubScreen extends ConsumerWidget {
  const new({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupProvider(groupId)).value;
    final permissions = ref.watch(groupPermissionsProvider(groupId));
    final members = ref.watch(membersProvider(groupId));
    final invites = ref.watch(invitesProvider(groupId));
    for (final value in [members, invites]) {
      if (value case AsyncError(:final error) when isGroupNotFound(error)) {
        return const GroupNotFoundView();
      }
    }
    // GroupShell only shows this tab once the group has loaded.
    if (group == null || permissions == null) return const LoadingView();

    final me = [
      for (final member in members.value ?? const <Member>[])
        if (permissions.isMe(member)) member,
    ].firstOrNull;

    return RefreshIndicator(
      // Failures show up in the sections.
      onRefresh: () => settled([
        ref.refresh(groupProvider(groupId).future),
        ref.refresh(membersProvider(groupId).future),
        ref.refresh(invitesProvider(groupId).future),
      ]),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _GroupHeader(group: group),
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.dynamic_feed_outlined),
                      title: Text(context.l10n.whatsNew),
                      subtitle: Text(context.l10n.whatsNewHelp),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          unawaited(context.push(Routes.groupFeed(groupId))),
                    ),
                    ListTile(
                      leading: const Icon(Icons.auto_awesome_outlined),
                      title: Text(context.l10n.recap),
                      subtitle: Text(context.l10n.recapHelp),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          unawaited(context.push(Routes.groupRecap(groupId))),
                    ),
                  ],
                ),
              ),
              _Section(
                title: context.l10n.members,
                trailing: Text('${group.memberCount}'),
                child: AsyncValueView(
                  value: members,
                  onRetry: () => ref.invalidate(membersProvider(groupId)),
                  data: (members) => MembersList(
                    group: group,
                    members: members,
                    permissions: permissions,
                  ),
                ),
              ),
              if (me != null)
                _Section(
                  title: context.l10n.mySettings,
                  child: MySettingsTile(groupId: groupId, me: me),
                ),
              _Section(
                title: context.l10n.invites,
                child: InvitesSection(group: group, permissions: permissions),
              ),
              _Section(
                title: context.l10n.tabGroup,
                child: GroupActions(group: group, permissions: permissions),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const new({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final description = group.description;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GroupAvatar(
            name: group.name,
            emoji: group.emoji,
            color: group.color,
            radius: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.name, style: textTheme.headlineSmall),
                if (description != null && description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(description),
                ],
                const SizedBox(height: 4),
                Text(
                  '${group.currency} · ${group.timezone}',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const new({required this.title, required this.child, this.trailing});

  final String title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: textTheme.titleMedium)),
                ?trailing,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

/// Edit (admin+), leave, and delete (owner).
class GroupActions extends ConsumerStatefulWidget {
  const new({required this.group, required this.permissions, super.key});

  final Group group;
  final GroupPermissions permissions;

  @override
  ConsumerState<GroupActions> createState() => _GroupActionsState();
}

class _GroupActionsState extends ConsumerState<GroupActions> {
  bool _busy = false;

  Group get _group => widget.group;

  /// Leaves the group. The owner of a group with other members gets `409
  /// owner_must_transfer` and goes through the transfer flow; the only
  /// member confirms that leaving deletes the group.
  Future<void> _leave() async {
    final l10n = context.l10n;
    final isOwner = widget.permissions.myRole.isOwner;
    var alone = false;
    setState(() => _busy = true);
    if (isOwner) {
      // Count again: leaving as the only member deletes the group.
      try {
        final members = await ref.refresh(membersProvider(_group.id).future);
        alone = members.length <= 1;
      } on Object {
        alone = _group.memberCount <= 1;
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final confirmed = await showConfirmDialog(
      context,
      title: alone
          ? l10n.leaveAndDeleteTitle(_group.name)
          : l10n.leaveTitle(_group.name),
      message: alone
          ? l10n.leaveAloneMessage
          : isOwner
          ? l10n.leaveOwnerMessage
          : l10n.leaveMemberMessage,
      confirmLabel: alone ? l10n.leaveAndDelete : l10n.leave,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final controller = ref.read(groupsControllerProvider.notifier);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    ApiException? failure;
    try {
      await controller.leave(_group.id);
    } on ApiException catch (e) {
      failure = e;
    }
    if (mounted) setState(() => _busy = false);
    switch (failure) {
      case null:
        router.go(Routes.groups);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              alone
                  ? l10n.groupDeleted(_group.name)
                  : l10n.youLeftGroup(_group.name),
            ),
          ),
        );
      case ProblemException(code: ErrorCodes.ownerMustTransfer):
        if (!mounted) return;
        final done = await showTransferOwnershipDialog(
          context,
          groupId: _group.id,
          groupName: _group.name,
          leaving: true,
        );
        if (done) {
          router.go(Routes.groups);
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.youLeftGroup(_group.name))),
          );
        }
      case final error:
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              friendlyErrorMessage(error, messages: groupErrorMessages),
            ),
          ),
        );
    }
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.deleteGroupTitle(_group.name),
      message: l10n.deleteGroupMessage,
      confirmLabel: l10n.deleteGroup,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final controller = ref.read(groupsControllerProvider.notifier);
    final router = GoRouter.of(context);
    setState(() => _busy = true);
    final deleted = await runGroupAction(
      context,
      () => controller.deleteGroup(_group.id),
      success: l10n.groupDeleted(_group.name),
    );
    if (deleted) router.go(Routes.groups);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.category_outlined),
          title: Text(context.l10n.categories),
          subtitle: Text(context.l10n.categoriesHelp),
          enabled: !_busy,
          onTap: () =>
              unawaited(context.push(Routes.groupCategories(_group.id))),
        ),
        if (widget.permissions.canEditGroup)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.edit_outlined),
            title: Text(context.l10n.editGroup),
            enabled: !_busy,
            onTap: () => unawaited(context.push(Routes.editGroup(_group.id))),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.logout),
          title: Text(context.l10n.leaveGroup),
          enabled: !_busy,
          onTap: () => unawaited(_leave()),
        ),
        if (widget.permissions.canDeleteGroup)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_forever, color: colors.error),
            title: Text(
              context.l10n.deleteGroup,
              style: TextStyle(color: colors.error),
            ),
            enabled: !_busy,
            onTap: () => unawaited(_delete()),
          ),
      ],
    );
  }
}
