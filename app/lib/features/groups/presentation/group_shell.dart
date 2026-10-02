import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/core/widgets/profile_avatar_button.dart';
import 'package:friends/features/groups/data/group_providers.dart';
import 'package:friends/features/groups/data/last_group_store.dart';
import 'package:friends/features/groups/presentation/widgets/group_avatar.dart';
import 'package:friends/features/groups/presentation/widgets/group_not_found_view.dart';
import 'package:friends/features/groups/presentation/widgets/group_themed.dart';
import 'package:friends/features/invites/presentation/join_with_code_dialog.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// The frame around a group's tabs (`/groups/:groupId/…`, a plain
/// `ShellRoute`): an app bar with the group switcher and my avatar, the
/// bottom navigation (Backlog, Books in a book club, Calendar, Wheel,
/// Group), and a theme seeded from the group's colour.
///
/// Remembers the group as the last one opened (`LastGroupStore`), and
/// shows "Group not found" when the group answers 404.
class GroupShell extends ConsumerStatefulWidget {
  const new({
    required this.groupId,
    required this.location,
    required this.child,
    super.key,
  });

  final String groupId;

  /// The current path, which selects the bottom tab.
  final String location;

  /// The current tab's page (the shell's navigator).
  final Widget child;

  @override
  ConsumerState<GroupShell> createState() => _GroupShellState();
}

class _GroupShellState extends ConsumerState<GroupShell> {
  ProviderSubscription<AsyncValue<Group>>? _remember;

  @override
  void initState() {
    super.initState();
    _rememberGroup();
  }

  @override
  void didUpdateWidget(GroupShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupId != widget.groupId) _rememberGroup();
  }

  /// Stores the group as the last opened one once it has loaded (so I am a
  /// member).
  void _rememberGroup() {
    _remember?.close();
    final groupId = widget.groupId;
    _remember = ref.listenManual(groupProvider(groupId), (_, next) {
      if (next.hasValue && !next.hasError) {
        unawaited(ref.read(lastGroupStoreProvider).write(groupId));
      }
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    final groupId = widget.groupId;
    final group = ref.watch(groupProvider(groupId));
    if (group case AsyncError(:final error) when isGroupNotFound(error)) {
      return const GroupNotFoundScreen();
    }
    // A failed refresh keeps showing the group (mutations report their own
    // errors); only a first load that fails shows the error.
    if (group.value case final data?) {
      return _GroupScaffold(
        group: data,
        tab: GroupTab.fromPath(widget.location) ?? GroupTab.backlog,
        child: widget.child,
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.l10n.allGroups,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(Routes.groups),
        ),
        actions: const [ProfileAvatarButton()],
      ),
      body: group.hasError
          ? ErrorView(
              error: group.error!,
              onRetry: () => ref.invalidate(groupProvider(groupId)),
            )
          : const LoadingView(),
    );
  }
}

class _GroupScaffold extends StatelessWidget {
  const new({required this.group, required this.tab, required this.child});

  final Group group;
  final GroupTab tab;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // A Books link still works in a group that isn't a book club (the kind
    // changed, or a link was shared): the tab shows while it is open.
    final tabs = tabsOf(group.kind, showBooks: tab == GroupTab.books);
    return GroupColorTheme(
      color: group.color,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 8,
          title: GroupSwitcher(current: group),
          actions: const [ProfileAvatarButton(), SizedBox(width: 8)],
        ),
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: tabs.indexOf(tab),
          onDestinationSelected: (index) =>
              context.go(Routes.groupTab(group.id, tabs[index])),
          destinations: [
            for (final tab in tabs) _destination(context, tab, group.kind),
          ],
        ),
      ),
    );
  }

  static NavigationDestination _destination(
    BuildContext context,
    GroupTab tab,
    GroupKind kind,
  ) => switch (tab) {
    GroupTab.backlog => NavigationDestination(
      icon: Icon(
        kind == GroupKind.movieNight ? Icons.movie_outlined : Icons.checklist,
      ),
      label: kind == GroupKind.movieNight
          ? context.l10n.tabMovies
          : context.l10n.tabBacklog,
    ),
    GroupTab.books => NavigationDestination(
      icon: const Icon(Icons.menu_book_outlined),
      selectedIcon: const Icon(Icons.menu_book),
      label: context.l10n.tabBooks,
    ),
    GroupTab.calendar => NavigationDestination(
      icon: const Icon(Icons.calendar_month_outlined),
      selectedIcon: const Icon(Icons.calendar_month),
      label: context.l10n.tabCalendar,
    ),
    GroupTab.wheel => NavigationDestination(
      icon: const Icon(Icons.casino_outlined),
      selectedIcon: const Icon(Icons.casino),
      label: context.l10n.tabWheel,
    ),
    GroupTab.group => NavigationDestination(
      icon: const Icon(Icons.groups_outlined),
      selectedIcon: const Icon(Icons.groups),
      label: context.l10n.tabGroup,
    ),
  };
}

/// A group's bottom tabs, in order: Books comes second in a book club (or
/// when [showBooks]), and isn't there otherwise.
List<GroupTab> tabsOf(GroupKind kind, {bool showBooks = false}) => [
  GroupTab.backlog,
  if (kind == GroupKind.bookClub || showBooks) GroupTab.books,
  GroupTab.calendar,
  GroupTab.wheel,
  GroupTab.group,
];

/// The app bar title of a group: its avatar and name, opening a menu with
/// my other groups, "All groups", "New group" and "Join with code".
class GroupSwitcher extends ConsumerWidget {
  const new({required this.current, super.key});

  final Group current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider).value ?? const [];
    return PopupMenuButton<VoidCallback>(
      tooltip: context.l10n.switchGroup,
      position: PopupMenuPosition.under,
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        for (final group in groups)
          PopupMenuItem(
            value: () => context.go(Routes.groupBacklog(group.id)),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: GroupAvatar(
                name: group.name,
                emoji: group.emoji,
                color: group.color,
                radius: 16,
              ),
              title: Text(group.name, overflow: TextOverflow.ellipsis),
              trailing: group.id == current.id ? const Icon(Icons.check) : null,
            ),
          ),
        if (groups.isNotEmpty) const PopupMenuDivider(),
        PopupMenuItem(
          value: () => context.go(Routes.groups),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.view_list_outlined),
            title: Text(context.l10n.allGroups),
          ),
        ),
        PopupMenuItem(
          value: () => unawaited(context.push(Routes.newGroup)),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.add),
            title: Text(context.l10n.newGroup),
          ),
        ),
        PopupMenuItem(
          value: () => unawaited(joinWithCode(context)),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.vpn_key_outlined),
            title: Text(context.l10n.joinWithCode),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GroupAvatar(
              name: current.name,
              emoji: current.emoji,
              color: current.color,
              radius: 16,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(current.name, overflow: TextOverflow.ellipsis),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}
