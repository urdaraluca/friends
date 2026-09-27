import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/core/widgets/profile_avatar_button.dart';
import 'package:friends/features/groups/data/group_providers.dart';
import 'package:friends/features/groups/presentation/widgets/group_avatar.dart';
import 'package:friends/features/groups/presentation/widgets/role_badge.dart';
import 'package:friends/features/invites/presentation/join_with_code_dialog.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// My groups (`/groups`): a card per group, pull to refresh, "New group"
/// and "Join with code".
class GroupsListScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.yourGroups),
        actions: [
          IconButton(
            tooltip: context.l10n.myCalendar,
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => unawaited(context.push(Routes.myCalendar)),
          ),
          PopupMenuButton<VoidCallback>(
            tooltip: context.l10n.more,
            onSelected: (action) => action(),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: () => unawaited(joinWithCode(context)),
                child: ListTile(
                  leading: const Icon(Icons.vpn_key_outlined),
                  title: Text(context.l10n.joinWithCode),
                ),
              ),
            ],
          ),
          const ProfileAvatarButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(context.push(Routes.newGroup)),
        icon: const Icon(Icons.add),
        label: Text(context.l10n.newGroup),
      ),
      body: AsyncValueView(
        value: ref.watch(groupsProvider),
        onRetry: () => ref.invalidate(groupsProvider),
        data: (groups) => RefreshIndicator(
          // A failure shows up as the error view.
          onRefresh: () => settled([ref.refresh(groupsProvider.future)]),
          child: groups.isEmpty
              ? const _NoGroups()
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  // Room for the FAB below the last card.
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: groups.length,
                  itemBuilder: (context, index) =>
                      GroupCard(group: groups[index]),
                ),
        ),
      ),
    );
  }
}

/// One group in the list: emoji and colour, name, member count, my role.
class GroupCard extends StatelessWidget {
  const new({required this.group, super.key});

  final GroupSummary group;

  @override
  Widget build(BuildContext context) {
    final count = group.memberCount;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: GroupAvatar(
          name: group.name,
          emoji: group.emoji,
          color: group.color,
          radius: 24,
        ),
        title: Text(group.name),
        subtitle: Text(context.l10n.memberCount(count)),
        trailing: RoleBadge(group.myRole),
        onTap: () => context.go(Routes.groupBacklog(group.id)),
      ),
    );
  }
}

class _NoGroups extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Scrollable, so pull to refresh works on the empty state too.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 48),
        const Icon(Icons.diversity_3, size: 64),
        const SizedBox(height: 16),
        Text(
          context.l10n.noGroupsYet,
          style: textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(context.l10n.noGroupsHelp, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton.icon(
            onPressed: () => unawaited(joinWithCode(context)),
            icon: const Icon(Icons.vpn_key_outlined),
            label: Text(context.l10n.joinWithCode),
          ),
        ),
      ],
    );
  }
}
