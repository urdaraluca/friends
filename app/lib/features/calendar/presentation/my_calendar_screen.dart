import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/date_only.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/features/calendar/data/calendar_providers.dart';
import 'package:friends/features/calendar/domain/occurrence_index.dart';
import 'package:friends/features/calendar/presentation/calendar_screen.dart';
import 'package:friends/features/calendar/presentation/widgets/calendar_view.dart';
import 'package:friends/features/groups/data/group_providers.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// `/calendar?day=YYYY-MM-DD`: every group's events and birthdays in one
/// view (`GET /me/calendar`). Each item names its group; tapping an event
/// opens it in its group.
class MyCalendarScreen extends ConsumerStatefulWidget {
  const new({this.initialDay, super.key});

  /// The day to open on, else today.
  final DateTime? initialDay;

  @override
  ConsumerState<MyCalendarScreen> createState() => _MyCalendarScreenState();
}

class _MyCalendarScreenState extends ConsumerState<MyCalendarScreen> {
  late DateTime _selected = _localDay(widget.initialDay ?? DateTime.now());
  late DateTime _focused = _selected;

  static DateTime _localDay(DateTime day) =>
      DateTime(day.year, day.month, day.day);

  CalendarQuery _query(CalendarSpan span) {
    final start = gridStart(_focused, span);
    return CalendarQuery(
      from: DateOnly.from(start),
      // Calendar days, not 24-hour steps: a DST change must not shift `to`.
      to: DateOnly.of(start.year, start.month, start.day + gridDays(span)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final span =
        ref.watch(calendarSpanSettingProvider).value ?? CalendarSpan.month;
    final query = _query(span);
    final calendar = ref.watch(myCalendarProvider(query));
    final index = OccurrenceIndex(calendar.value?.occurrences ?? const []);
    final groups = {
      for (final group
          in ref.watch(groupsProvider).value ?? const <GroupSummary>[])
        group.id: group.name,
    };
    final occurrences = index.on(_selected);
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: context.canPop()
            ? null
            : IconButton(
                tooltip: 'Home',
                icon: const Icon(Icons.home_outlined),
                onPressed: () => context.go(Routes.home),
              ),
        title: const Text('My calendar'),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            settled([ref.refresh(myCalendarProvider(query).future)]),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
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
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                DateFormat('EEEE d MMMM').format(_selected),
                style: textTheme.titleMedium,
              ),
            ),
            if (calendar.hasError && !calendar.hasValue)
              ErrorView(
                error: calendar.error!,
                onRetry: () => ref.invalidate(myCalendarProvider(query)),
              )
            else if (calendar.isLoading && !calendar.hasValue)
              const Padding(padding: EdgeInsets.all(16), child: LoadingView())
            else if (occurrences.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Nothing planned in any of your groups.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final occurrence in occurrences)
                _MyAgendaTile(
                  occurrence: occurrence,
                  groupName: groups[occurrence.groupId],
                ),
          ],
        ),
      ),
    );
  }
}

/// An occurrence with its group's name.
class _MyAgendaTile extends StatelessWidget {
  const new({required this.occurrence, required this.groupName});

  final Occurrence occurrence;
  final String? groupName;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final memberBirthday = occurrence.source == OccurrenceSource.memberBirthday;
    final groupId = occurrence.groupId;
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
      subtitle: Text([?groupName, AgendaTile.when(occurrence)].join(' · ')),
      trailing: occurrence.isRecurring && !memberBirthday
          ? const Icon(Icons.repeat, size: 18)
          : null,
      onTap: groupId == null || eventId == null
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
