import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/date_only.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/features/backlog/data/backlog_providers.dart';
import 'package:friends/features/backlog/domain/category_index.dart';
import 'package:friends/features/backlog/presentation/widgets/category_picker.dart';
import 'package:friends/features/calendar/data/calendar_providers.dart';
import 'package:friends/features/calendar/domain/occurrence_index.dart';
import 'package:friends/features/calendar/presentation/widgets/calendar_view.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// The Calendar tab (`/groups/:groupId/calendar?day=YYYY-MM-DD`): the grid
/// with markers, filters, and the selected day's agenda.
class CalendarScreen extends ConsumerStatefulWidget {
  const new({required this.groupId, this.initialDay, super.key});

  final String groupId;

  /// The day to open on (from `?day=`), else today.
  final DateTime? initialDay;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _selected = _localDay(widget.initialDay ?? DateTime.now());
  late DateTime _focused = _selected;

  static DateTime _localDay(DateTime day) =>
      DateTime(day.year, day.month, day.day);

  CalendarQuery _query(CalendarSpan span, CalendarFilters filters) {
    final start = gridStart(_focused, span);
    return CalendarQuery(
      from: DateOnly.from(start),
      // Calendar days, not 24-hour steps: a DST change must not shift `to`.
      to: DateOnly.of(start.year, start.month, start.day + gridDays(span)),
      kinds: filters.kinds,
      categoryId: filters.categoryId,
    );
  }

  void _toggleKind(CalendarFilters filters, EventKind kind) {
    final kinds = filters.kinds.isEmpty
        ? {...EventKind.$valuesDefined}
        : {...filters.kinds};
    if (!kinds.remove(kind)) kinds.add(kind);
    // Keep at least one kind; all of them means no filter.
    if (kinds.isEmpty) return;
    final all = kinds.length == EventKind.$valuesDefined.length;
    ref
        .read(calendarFilterProvider(widget.groupId).notifier)
        .set(filters.copyWith(kinds: all || kinds.isEmpty ? {} : kinds));
  }

  @override
  Widget build(BuildContext context) {
    final groupId = widget.groupId;
    final span =
        ref.watch(calendarSpanSettingProvider).value ?? CalendarSpan.month;
    final filters = ref.watch(calendarFilterProvider(groupId));
    final categories =
        ref.watch(categoryIndexProvider(groupId)).value ??
        CategoryIndex.empty();
    final query = _query(span, filters);
    final calendar = ref.watch(calendarProvider(groupId, query));
    final index = OccurrenceIndex(calendar.value?.occurrences ?? const []);

    bool shown(EventKind kind) =>
        filters.kinds.isEmpty || filters.kinds.contains(kind);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-event',
        onPressed: () => unawaited(
          context.push(
            Routes.newEvent(groupId, date: DateOnly.format(_selected)),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New event'),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            settled([ref.refresh(calendarProvider(groupId, query).future)]),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  for (final (kind, label) in const [
                    (EventKind.birthday, 'Birthdays'),
                    (EventKind.oneTime, 'One-time'),
                    (EventKind.recurring, 'Recurring'),
                  ]) ...[
                    FilterChip(
                      label: Text(label),
                      selected: shown(kind),
                      onSelected: (_) => _toggleKind(filters, kind),
                    ),
                    const SizedBox(width: 6),
                  ],
                  InputChip(
                    avatar: const Icon(Icons.category_outlined, size: 18),
                    label: Text(
                      categories.name(filters.categoryId) ?? 'Category',
                    ),
                    selected: filters.categoryId != null,
                    showCheckmark: false,
                    onPressed: () async {
                      final choice = await showCategoryPicker(
                        context,
                        index: categories,
                        selectedId: filters.categoryId,
                        noneLabel: 'All categories',
                      );
                      if (choice is PickedCategory) {
                        ref
                            .read(calendarFilterProvider(groupId).notifier)
                            .set(filters.copyWith(categoryId: () => choice.id));
                      }
                    },
                    onDeleted: filters.categoryId == null
                        ? null
                        : () => ref
                              .read(calendarFilterProvider(groupId).notifier)
                              .set(filters.copyWith(categoryId: () => null)),
                  ),
                ],
              ),
            ),
            CalendarView(
              focusedDay: _focused,
              selectedDay: _selected,
              span: span,
              index: index,
              onDaySelected: (day) => setState(() {
                _selected = _localDay(day);
                _focused = _selected;
              }),
              onPageChanged: (focused) =>
                  setState(() => _focused = _localDay(focused)),
              onSpanChanged: (span) => unawaited(
                ref.read(calendarSpanSettingProvider.notifier).set(span),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: OutlinedButton.icon(
                onPressed: () => unawaited(
                  context.push(
                    Routes.groupAvailability(
                      groupId,
                      month: DateOnly.format(_focused),
                    ),
                  ),
                ),
                icon: const Icon(Icons.group_outlined),
                label: const Text('When can everyone make it?'),
              ),
            ),
            const Divider(height: 1),
            if (calendar.hasError && !calendar.hasValue)
              ErrorView(
                error: calendar.error!,
                onRetry: () => ref.invalidate(calendarProvider(groupId, query)),
              )
            else
              DayAgenda(
                groupId: groupId,
                day: _selected,
                occurrences: index.on(_selected),
                loading: calendar.isLoading && !calendar.hasValue,
              ),
          ],
        ),
      ),
    );
  }
}

/// The selected day's occurrences: all-day ones first, then timed ones in
/// device-local time (no timezone label, contract section 5.5).
class DayAgenda extends StatelessWidget {
  const new({
    required this.groupId,
    required this.day,
    required this.occurrences,
    this.loading = false,
    super.key,
  });

  final String groupId;
  final DateTime day;
  final List<Occurrence> occurrences;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              DateFormat('EEEE d MMMM').format(day),
              style: textTheme.titleMedium,
            ),
          ),
          if (loading)
            const Padding(padding: EdgeInsets.all(16), child: LoadingView())
          else if (occurrences.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Nothing planned.',
                style: textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final occurrence in occurrences)
              AgendaTile(groupId: groupId, occurrence: occurrence),
        ],
      ),
    );
  }
}

/// One occurrence in the agenda.
class AgendaTile extends StatelessWidget {
  const new({required this.groupId, required this.occurrence, super.key});

  final String groupId;
  final Occurrence occurrence;

  /// "19:00–22:00", "All day", or "3 Oct – 5 Oct" for several days.
  static String when(Occurrence occurrence) {
    if (occurrence.allDay || occurrence.startsAt == null) {
      final start = occurrence.startDate;
      final end = occurrence.endDate;
      if (start == null) return 'All day';
      if (end == null || DateOnly.isSameDay(start, end)) return 'All day';
      final format = DateFormat('d MMM');
      return '${format.format(start)} – ${format.format(end)}';
    }
    final time = DateFormat.Hm();
    final start = occurrence.startsAt!.toLocal();
    final end = occurrence.endsAt?.toLocal();
    return end == null
        ? time.format(start)
        : '${time.format(start)}–${time.format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final memberBirthday = occurrence.source == OccurrenceSource.memberBirthday;
    final eventId = occurrence.eventId;
    return ListTile(
      leading: occurrence.kind == EventKind.birthday
          ? const Text('🎂', style: TextStyle(fontSize: 22))
          : Container(
              width: 6,
              height: 36,
              decoration: BoxDecoration(
                color: occurrenceColor(occurrence, colors),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
      title: Text(
        memberBirthday ? "${occurrence.title}'s birthday" : occurrence.title,
      ),
      subtitle: Text(when(occurrence)),
      trailing: occurrence.isRecurring && !memberBirthday
          ? const Icon(Icons.repeat, size: 18)
          : null,
      onTap: eventId == null
          ? null
          : () => unawaited(
              context.push(
                Routes.event(
                  groupId,
                  eventId,
                  occurrence: occurrence.occurrenceKey,
                ),
              ),
            ),
    );
  }
}
