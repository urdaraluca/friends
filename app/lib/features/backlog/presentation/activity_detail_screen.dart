import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/links/open_link.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/core/widgets/confirm_dialog.dart';
import 'package:friends/core/widgets/user_avatar.dart';
import 'package:friends/core/widgets/version_conflict_dialog.dart';
import 'package:friends/features/backlog/data/backlog_controller.dart';
import 'package:friends/features/backlog/data/backlog_providers.dart';
import 'package:friends/features/backlog/domain/activity_rules.dart';
import 'package:friends/features/backlog/domain/category_index.dart';
import 'package:friends/features/backlog/presentation/widgets/activity_card.dart';
import 'package:friends/features/backlog/presentation/widgets/attributes_view.dart';
import 'package:friends/features/backlog/presentation/widgets/category_visuals.dart';
import 'package:friends/features/groups/data/group_providers.dart';
import 'package:friends/features/groups/presentation/widgets/group_themed.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// An activity (`/groups/:groupId/backlog/:activityId`): its status, owner,
/// interest, details and custom fields, linked plans and polls.
class ActivityDetailScreen extends ConsumerWidget {
  const new({required this.groupId, required this.activityId, super.key});

  final String groupId;
  final String activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(activityProvider(activityId));
    final loaded = activity.value;
    return GroupThemed(
      groupId: groupId,
      child: Scaffold(
        appBar: AppBar(
          title: Text(loaded?.title ?? 'Idea'),
          actions: [
            if (loaded != null)
              _ActivityMenu(groupId: groupId, activity: loaded),
          ],
        ),
        body: AsyncValueView(
          value: activity,
          onRetry: () => ref.invalidate(activityProvider(activityId)),
          data: (activity) => RefreshIndicator(
            onRefresh: () =>
                settled([ref.refresh(activityProvider(activityId).future)]),
            child: _ActivityBody(groupId: groupId, activity: activity),
          ),
        ),
      ),
    );
  }
}

class _ActivityMenu extends ConsumerWidget {
  const new({required this.groupId, required this.activity});

  final String groupId;
  final Activity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      onSelected: (action) => switch (action) {
        'edit' => unawaited(
          context.push(Routes.editActivity(groupId, activity.id)),
        ),
        'delete' => unawaited(_delete(context, ref)),
        _ => null,
      },
      itemBuilder: (context) => [
        if (activity.canEdit)
          const PopupMenuItem(
            value: 'edit',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.edit_outlined),
              title: Text('Edit'),
            ),
          ),
        if (activity.canDelete)
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline),
              title: Text('Delete'),
            ),
          ),
      ],
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete "${activity.title}"?',
      message:
          'Its polls and interests go with it. Linked plans stay in the '
          'calendar, unlinked.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref
          .read(backlogControllerProvider.notifier)
          .deleteActivity(activity.id);
      router.go(Routes.groupBacklog(groupId));
      messenger.showSnackBar(const SnackBar(content: Text('Idea deleted')));
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    }
  }
}

class _ActivityBody extends ConsumerWidget {
  const new({required this.groupId, required this.activity});

  final String groupId;
  final Activity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories =
        ref.watch(categoryIndexProvider(groupId)).value ??
        CategoryIndex.empty();
    final textTheme = Theme.of(context).textTheme;
    final cost = costLabel(
      cost: activity.estimatedCost,
      currency: activity.currency,
      perPerson: activity.costPerPerson,
    );
    final fieldDefs = categories.fieldDefs(activity.categoryId);

    Widget section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: textTheme.titleSmall),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _StatusMenu(activity: activity),
            CategoryLabel(index: categories, categoryId: activity.categoryId),
          ],
        ),
        const SizedBox(height: 16),
        _OwnerRow(groupId: groupId, activity: activity),
        const SizedBox(height: 8),
        _InterestRow(activity: activity),
        const Divider(height: 32),
        if (activity.dueDate case final due?)
          _InfoTile(
            icon: Icons.flag_outlined,
            text: 'Do it by ${DateFormat.yMMMd().format(due)}',
          ),
        if (cost != null) _InfoTile(icon: Icons.payments_outlined, text: cost),
        if (activity.locationName case final place?)
          _InfoTile(
            icon: Icons.place_outlined,
            text: place,
            onTap: () => openLink(
              context,
              ref,
              LinkOpener.mapsSearch([place, ?activity.address].join(', ')),
            ),
          ),
        if (activity.address case final address?)
          _InfoTile(
            icon: Icons.map_outlined,
            text: address,
            onTap: () => openLink(context, ref, LinkOpener.mapsSearch(address)),
          ),
        for (final link in activity.links)
          _InfoTile(
            icon: Icons.link,
            text: link.label ?? link.url,
            onTap: () {
              final uri = Uri.tryParse(link.url);
              if (uri != null) unawaited(openLink(context, ref, uri));
            },
          ),
        if (activity.description case final description?)
          section('Description', SelectableText(description)),
        if (fieldDefs.isNotEmpty &&
            activity.attributes is Map &&
            (activity.attributes as Map).isNotEmpty)
          section(
            'Details',
            AttributesView(
              fieldDefs: fieldDefs,
              attributes: activity.attributes,
            ),
          ),
        if (activity.notes case final notes?)
          section('Notes', SelectableText(notes)),
        section('Plans', _LinkedEvents(activity: activity)),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const new({required this.icon, required this.text, this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon),
      title: Text(
        text,
        style: onTap == null
            ? null
            : TextStyle(color: Theme.of(context).colorScheme.primary),
      ),
      trailing: onTap == null ? null : const Icon(Icons.open_in_new, size: 18),
      onTap: onTap,
    );
  }
}

class _StatusMenu extends ConsumerStatefulWidget {
  const new({required this.activity});

  final Activity activity;

  @override
  ConsumerState<_StatusMenu> createState() => _StatusMenuState();
}

class _StatusMenuState extends ConsumerState<_StatusMenu> {
  bool _saving = false;

  Future<void> _set(ActivityStatus status) async {
    if (status == widget.activity.status) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(backlogControllerProvider.notifier)
          .setStatus(widget.activity.id, status);
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ActivityStatus>(
      tooltip: 'Change status',
      enabled: !_saving,
      onSelected: (status) => unawaited(_set(status)),
      itemBuilder: (context) => [
        for (final status in ActivityStatus.$valuesDefined)
          CheckedPopupMenuItem(
            value: status,
            checked: status == widget.activity.status,
            child: Text(status.label),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusChip(status: widget.activity.status),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }
}

class _OwnerRow extends ConsumerStatefulWidget {
  const new({required this.groupId, required this.activity});

  final String groupId;
  final Activity activity;

  @override
  ConsumerState<_OwnerRow> createState() => _OwnerRowState();
}

class _OwnerRowState extends ConsumerState<_OwnerRow> {
  bool _saving = false;

  Future<void> _setOwner(String? ownerId) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(backlogControllerProvider.notifier)
          .updateActivity(
            widget.activity.id,
            activityUpdateFrom(widget.activity, ownerId: () => ownerId),
          );
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error case ProblemException(code: ErrorCodes.versionConflict)) {
        setState(() => _saving = false);
        await showVersionConflictDialog(context);
        ref.invalidate(activityProvider(widget.activity.id));
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickOwner() async {
    final members = await ref.read(membersProvider(widget.groupId).future);
    if (!mounted) return;
    final picked = await showDialog<_OwnerChoice>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Who is on it?'),
        children: [
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(context).pop(const _OwnerChoice(null)),
            child: const ListTile(
              leading: Icon(Icons.person_off_outlined),
              title: Text('Nobody'),
            ),
          ),
          for (final member in members)
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.of(context).pop(_OwnerChoice(member.user.id)),
              child: ListTile(
                leading: UserAvatar(user: member.user),
                title: Text(member.user.displayName),
                trailing: member.user.id == widget.activity.owner?.id
                    ? const Icon(Icons.check)
                    : null,
              ),
            ),
        ],
      ),
    );
    if (picked != null && picked.userId != widget.activity.owner?.id) {
      await _setOwner(picked.userId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserIdProvider);
    final role = ref.watch(myRoleProvider(widget.groupId));
    final owner = widget.activity.owner;
    final rules = me == null || role == null
        ? null
        : OwnerRules(myRole: role, myUserId: me, ownerId: owner?.id);
    return Row(
      children: [
        if (owner != null)
          UserAvatar(user: owner)
        else
          const CircleAvatar(radius: 16, child: Icon(Icons.person_outline)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            owner == null
                ? 'Nobody is on it yet'
                : owner.id == me
                ? "You're on it"
                : '${owner.displayName} is on it',
          ),
        ),
        if (_saving)
          const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (rules != null && rules.canHandOff)
          TextButton(
            onPressed: () => unawaited(_pickOwner()),
            child: Text(owner == null ? 'Assign' : 'Change'),
          )
        else if (rules != null && rules.canClaim)
          TextButton(
            onPressed: () => unawaited(_setOwner(me)),
            child: const Text("I'll do it"),
          ),
      ],
    );
  }
}

class _OwnerChoice {
  const new(this.userId);

  final String? userId;
}

class _InterestRow extends ConsumerStatefulWidget {
  const new({required this.activity});

  final Activity activity;

  @override
  ConsumerState<_InterestRow> createState() => _InterestRowState();
}

class _InterestRowState extends ConsumerState<_InterestRow> {
  /// My interest while a toggle is on its way (optimistic), else null.
  bool? _pending;

  Future<void> _toggle() async {
    final messenger = ScaffoldMessenger.of(context);
    final interested = !widget.activity.iAmInterested;
    setState(() => _pending = interested);
    try {
      await ref
          .read(backlogControllerProvider.notifier)
          .setInterest(widget.activity.id, interested: interested);
      ref.invalidate(activitiesPagerProvider);
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activity = widget.activity;
    final interested = _pending ?? activity.iAmInterested;
    final count =
        activity.interestCount + (_pending == null ? 0 : (interested ? 1 : -1));
    return Row(
      children: [
        AvatarStack(users: activity.interestedUsers),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            count == 0 ? 'Nobody is interested yet' : '$count interested',
          ),
        ),
        FilterChip(
          avatar: Icon(
            interested ? Icons.favorite : Icons.favorite_border,
            size: 18,
          ),
          showCheckmark: false,
          label: const Text("I'm interested"),
          selected: interested,
          onSelected: _pending == null ? (_) => unawaited(_toggle()) : null,
        ),
      ],
    );
  }
}

class _LinkedEvents extends StatelessWidget {
  const new({required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) {
    if (activity.events.isEmpty) {
      return Text(
        'Not in the calendar yet.',
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    return Column(
      children: [
        for (final event in activity.events)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(event.rrule == null ? Icons.event : Icons.repeat),
            title: Text(event.title),
            subtitle: Text(eventRefWhen(event)),
          ),
      ],
    );
  }
}

/// When an event starts: "Sat 3 Oct 2026, 19:00" (device-local, no zone
/// label) or "Sat 3 Oct 2026" for all-day ones; "every …" when recurring.
String eventRefWhen(EventRef event) {
  final start = switch (event) {
    EventRef(:final startsAt?) => DateFormat(
      'EEE d MMM y, HH:mm',
    ).format(startsAt.toLocal()),
    EventRef(:final startDate?) => DateFormat('EEE d MMM y').format(startDate),
    _ => '',
  };
  return event.rrule == null ? start : 'Repeats, from $start';
}
