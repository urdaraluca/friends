import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/date_only.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/links/open_link.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/core/widgets/confirm_dialog.dart';
import 'package:friends/features/backlog/data/backlog_providers.dart';
import 'package:friends/features/backlog/domain/category_index.dart';
import 'package:friends/features/backlog/presentation/widgets/category_visuals.dart';
import 'package:friends/features/calendar/data/calendar_providers.dart';
import 'package:friends/features/calendar/domain/rrule_spec.dart';
import 'package:friends/features/groups/presentation/widgets/group_themed.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// An event (`/groups/:groupId/calendar/events/:eventId?occurrence=KEY`):
/// its time (the given occurrence's, if any), recurrence, category, linked
/// idea, place and description; with `can_edit`, edit, delete, and cancel
/// or restore single occurrences.
class EventDetailScreen extends ConsumerWidget {
  const new({
    required this.groupId,
    required this.eventId,
    this.occurrenceKey,
    super.key,
  });

  final String groupId;
  final String eventId;

  /// The occurrence the user tapped in the calendar, if any.
  final String? occurrenceKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(eventProvider(eventId));
    final loaded = event.value;
    return GroupThemed(
      groupId: groupId,
      child: Scaffold(
        appBar: AppBar(
          title: Text(loaded?.title ?? 'Event'),
          actions: [
            if (loaded != null && loaded.canEdit)
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => unawaited(
                  context.push(Routes.editEvent(groupId, loaded.id)),
                ),
              ),
            if (loaded != null && loaded.canDelete)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => unawaited(_delete(context, ref, loaded)),
              ),
          ],
        ),
        body: AsyncValueView(
          value: event,
          onRetry: () => ref.invalidate(eventProvider(eventId)),
          data: (event) => _EventBody(
            groupId: groupId,
            event: event,
            occurrenceKey: occurrenceKey,
          ),
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Event event) async {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete "${event.title}"?',
      message: event.kind == EventKind.oneTime
          ? 'It disappears from the calendar.'
          : 'Every occurrence goes. To skip just one, cancel that occurrence '
                'instead.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(eventsControllerProvider.notifier).delete(event);
      router.go(Routes.calendar(groupId));
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    }
  }
}

/// When one occurrence of [event] starts and ends, from its [key].
({DateTime? start, DateTime? end, DateTime? startDate, DateTime? endDate})
occurrenceTimes(Event event, String? key) {
  final startsAt = event.startsAt;
  final endsAt = event.endsAt;
  if (!event.allDay && startsAt != null && endsAt != null) {
    final start = key == null ? startsAt : _keyInstant(key) ?? startsAt;
    return (
      start: start,
      end: start.add(endsAt.difference(startsAt)),
      startDate: null,
      endDate: null,
    );
  }
  final firstDay = DateOnly.fromNullable(event.startDate);
  final lastDay = DateOnly.fromNullable(event.endDate) ?? firstDay;
  if (firstDay == null) {
    return (start: null, end: null, startDate: null, endDate: null);
  }
  final day = key == null ? firstDay : _keyDate(key) ?? firstDay;
  return (
    start: null,
    end: null,
    startDate: day,
    endDate: day.add(lastDay!.difference(firstDay)),
  );
}

DateTime? _keyInstant(String key) {
  final match = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$')
      .firstMatch(key);
  if (match == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  return DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
}

DateTime? _keyDate(String key) {
  final match = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(key);
  if (match == null) return null;
  return DateOnly.of(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

/// "Every week on Thursday", "Every year (birthday)", or null for one-time
/// events.
String? recurrenceSummary(Event event) {
  final rule = event.rrule;
  if (rule == null) return null;
  if (event.kind == EventKind.birthday) return 'Every year';
  return RecurrenceSpec.tryParse(rule)?.describe() ?? 'Repeats ($rule)';
}

class _EventBody extends ConsumerStatefulWidget {
  const new({
    required this.groupId,
    required this.event,
    required this.occurrenceKey,
  });

  final String groupId;
  final Event event;
  final String? occurrenceKey;

  @override
  ConsumerState<_EventBody> createState() => _EventBodyState();
}

class _EventBodyState extends ConsumerState<_EventBody> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final key = widget.occurrenceKey;
    final controller = ref.read(eventsControllerProvider.notifier);
    final categories =
        ref.watch(categoryIndexProvider(widget.groupId)).value ??
        CategoryIndex.empty();
    final activityId = event.activityId;
    final activity = activityId == null
        ? null
        : ref.watch(activityProvider(activityId)).value;
    final times = occurrenceTimes(event, key);
    final repeats = recurrenceSummary(event);
    final cancelled = event.cancelledOccurrenceKeys;
    final canCancel =
        event.canEdit &&
        key != null &&
        event.kind != EventKind.oneTime &&
        !cancelled.contains(key);

    String when() {
      if (times.start case final start?) {
        final day = DateFormat('EEEE d MMMM y');
        final time = DateFormat.Hm();
        final end = times.end!;
        final local = start.toLocal();
        final localEnd = end.toLocal();
        return DateOnly.isSameDay(local, localEnd)
            ? '${day.format(local)}\n${time.format(local)}–'
                  '${time.format(localEnd)}'
            : '${day.format(local)}, ${time.format(local)} –\n'
                  '${day.format(localEnd)}, ${time.format(localEnd)}';
      }
      final day = DateFormat('EEEE d MMMM y');
      final startDate = times.startDate;
      final endDate = times.endDate;
      if (startDate == null) return '';
      return endDate == null || DateOnly.isSameDay(startDate, endDate)
          ? '${day.format(startDate)} · All day'
          : '${day.format(startDate)} –\n${day.format(endDate)} · All day';
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            event.kind == EventKind.birthday
                ? Icons.cake_outlined
                : Icons.schedule,
          ),
          title: Text(when()),
          subtitle: repeats == null ? null : Text(repeats),
        ),
        if (event.categoryId != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.category_outlined),
            title: CategoryLabel(
              index: categories,
              categoryId: event.categoryId,
            ),
          ),
        if (activityId != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lightbulb_outline),
            title: Text(activity?.title ?? 'The linked idea'),
            subtitle: const Text('From the backlog'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => unawaited(
              context.push(Routes.activity(widget.groupId, activityId)),
            ),
          ),
        if (event.locationName case final place?)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.place_outlined),
            title: Text(place),
            onTap: () => openLink(
              context,
              ref,
              LinkOpener.mapsSearch([place, ?event.address].join(', ')),
            ),
          ),
        if (event.address case final address?)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.map_outlined),
            title: Text(address),
            onTap: () => openLink(context, ref, LinkOpener.mapsSearch(address)),
          ),
        if (event.description case final description?)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SelectableText(description),
          ),
        if (canCancel)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => unawaited(
                      _run(
                        () => controller.cancelOccurrence(event, key),
                        'This occurrence is cancelled',
                      ),
                    ),
              icon: const Icon(Icons.event_busy),
              label: const Text('Cancel this occurrence'),
            ),
          ),
        if (cancelled.isNotEmpty) ...[
          const Divider(height: 32),
          Text('Cancelled', style: Theme.of(context).textTheme.titleSmall),
          for (final cancelledKey in cancelled)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_busy),
              title: Text(_keyLabel(event, cancelledKey)),
              trailing: event.canEdit
                  ? TextButton(
                      onPressed: _busy
                          ? null
                          : () => unawaited(
                              _run(
                                () => controller.restoreOccurrence(
                                  event,
                                  cancelledKey,
                                ),
                                'Restored',
                              ),
                            ),
                      child: const Text('Restore'),
                    )
                  : null,
            ),
        ],
      ],
    );
  }

  static String _keyLabel(Event event, String key) {
    final instant = _keyInstant(key);
    if (instant != null) {
      return DateFormat('EEE d MMM y, HH:mm').format(instant.toLocal());
    }
    final date = _keyDate(key);
    return date == null ? key : DateFormat('EEE d MMM y').format(date);
  }
}
