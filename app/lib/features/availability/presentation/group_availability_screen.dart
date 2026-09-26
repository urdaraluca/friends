import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/date_only.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/features/availability/data/availability_providers.dart';
import 'package:friends/features/availability/presentation/widgets/availability_style.dart';
import 'package:friends/features/availability/presentation/widgets/month_grid.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// `/groups/:groupId/calendar/availability`: "When can everyone make it?".
/// The group's heatmap for a month, its best days, and who is free on a day
/// (contract section 13). "Plan it" opens the event form on that day,
/// linked to [activityId] when it came from an idea (the wheel).
class GroupAvailabilityScreen extends ConsumerStatefulWidget {
  const new({
    required this.groupId,
    this.activityId,
    this.initialMonth,
    super.key,
  });

  final String groupId;
  final String? activityId;

  /// A day of the month to open on, else this month.
  final DateTime? initialMonth;

  @override
  ConsumerState<GroupAvailabilityScreen> createState() =>
      _GroupAvailabilityScreenState();
}

class _GroupAvailabilityScreenState
    extends ConsumerState<GroupAvailabilityScreen> {
  late DateTime _month = DateTime(
    (widget.initialMonth ?? DateTime.now()).year,
    (widget.initialMonth ?? DateTime.now()).month,
  );
  AvailabilitySlot _slot = AvailabilitySlot.allDay;

  Future<void> _editMine() async {
    await context.push(
      Routes.myAvailabilityFor(month: DateOnly.format(_month)),
    );
  }

  void _openDay(GroupAvailability data, DateTime day) {
    final key = DateOnly.format(day);
    final match = data.days.where((d) => DateOnly.format(d.date) == key);
    if (match.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => DaySheet(
        day: match.first,
        onPlan: () {
          Navigator.of(sheetContext).pop();
          unawaited(
            context.push(
              Routes.newEvent(
                widget.groupId,
                activityId: widget.activityId,
                date: key,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = groupAvailabilityProvider(widget.groupId, _month);
    final availability = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('When can everyone make it?'),
        actions: [
          IconButton(
            tooltip: 'My availability',
            icon: const Icon(Icons.edit_calendar_outlined),
            onPressed: () => unawaited(_editMine()),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => settled([ref.refresh(provider.future)]),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MonthHeader(
                      month: _month,
                      onChanged: (month) => setState(() => _month = month),
                    ),
                    SlotChips(
                      selected: _slot,
                      allDayLabel: 'Whole day',
                      onSelected: (slot) => setState(() => _slot = slot),
                    ),
                    const SizedBox(height: 8),
                    AsyncValueView(
                      value: availability,
                      onRetry: () => ref.invalidate(provider),
                      loading: const Padding(
                        padding: EdgeInsets.all(48),
                        child: LoadingView(),
                      ),
                      data: (data) => _Heatmap(
                        data: data,
                        month: _month,
                        slot: _slot,
                        onTapDay: (day) => _openDay(data, day),
                        onEditMine: () => unawaited(_editMine()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How warm a day looks: its slot's score (`free + 0.5 × maybe`) out of
/// everyone, 0 to 1.
double heat(SlotCounts counts, int memberCount) => memberCount == 0
    ? 0
    : ((counts.free + 0.5 * counts.maybe) / memberCount).clamp(0, 1);

class _Heatmap extends StatelessWidget {
  const new({
    required this.data,
    required this.month,
    required this.slot,
    required this.onTapDay,
    required this.onEditMine,
  });

  final GroupAvailability data;
  final DateTime month;
  final AvailabilitySlot slot;
  final ValueChanged<DateTime> onTapDay;
  final VoidCallback onEditMine;

  /// "2 free, 1 maybe", leaving out a zero.
  static String _tally(BestDay day) => [
    if (day.free > 0) '${day.free} free',
    if (day.maybe > 0) '${day.maybe} maybe',
  ].join(', ');

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final days = {for (final day in data.days) DateOnly.format(day.date): day};
    final best = {
      for (final day in data.bestDays.take(3)) DateOnly.format(day.date),
    };
    final chipDate = DateFormat('EEE d MMM');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text('Best days', style: textTheme.titleSmall),
        ),
        if (data.bestDays.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Nobody has said when they are free yet.'),
                ),
                TextButton(
                  onPressed: onEditMine,
                  child: const Text('Add mine'),
                ),
              ],
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final day in data.bestDays) ...[
                  ActionChip(
                    avatar: Icon(
                      Icons.star,
                      size: 18,
                      color: statusColor(AvailabilityStatus.free),
                    ),
                    label: Text(
                      '${chipDate.format(day.date)} · ${_tally(day)}',
                    ),
                    onPressed: () => onTapDay(day.date),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: MonthGrid(
            month: month,
            onTapDay: onTapDay,
            cellBuilder: (context, date) {
              final key = DateOnly.format(date);
              final day = days[key];
              final counts = day?.slots
                  .where((s) => s.slot == slot)
                  .firstOrNull;
              final warmth = counts == null
                  ? 0.0
                  : heat(counts, data.memberCount);
              final background = Color.lerp(
                colors.surfaceContainerHighest,
                statusColor(AvailabilityStatus.free),
                warmth,
              )!;
              final outside = date.month != month.month;
              return Semantics(
                button: true,
                excludeSemantics: true,
                label:
                    '${DateFormat('EEEE d MMMM').format(date)}: '
                    '${counts?.free ?? 0} free, ${counts?.maybe ?? 0} maybe',
                child: Padding(
                  key: ValueKey('heat-$key'),
                  padding: const EdgeInsets.all(2),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Text(
                            '${date.day}',
                            style: TextStyle(
                              color: warmth > 0.5
                                  ? onColor(background)
                                  : (outside
                                        ? colors.outline
                                        : colors.onSurface),
                              fontWeight: outside
                                  ? FontWeight.normal
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (best.contains(key))
                          Positioned(
                            top: 3,
                            right: 3,
                            child: Icon(
                              Icons.star,
                              size: 12,
                              color: onColor(background),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Fewer free', style: textTheme.bodySmall),
              const SizedBox(width: 8),
              for (final step in [0.0, 0.25, 0.5, 0.75, 1.0])
                Container(
                  width: 18,
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      colors.surfaceContainerHighest,
                      statusColor(AvailabilityStatus.free),
                      step,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              const SizedBox(width: 8),
              Text('Everyone', style: textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          data.memberCount == 1
              ? '1 member · tap a day to see who is free'
              : '${data.memberCount} members · tap a day to see who is free',
          textAlign: TextAlign.center,
          style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// A day of the heatmap: per slot, how many are free, maybe and busy, and
/// who is free or maybe. Busy is a count only (contract section 13).
class DaySheet extends StatelessWidget {
  const new({required this.day, required this.onPlan, super.key});

  final DayAvailability day;
  final VoidCallback onPlan;

  static String counts(SlotCounts counts) => [
    '${counts.free} free',
    if (counts.maybe > 0) '${counts.maybe} maybe',
    if (counts.busy > 0) '${counts.busy} busy',
    if (counts.unknown > 0) '${counts.unknown} not set',
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    String names(List<UserPublic> users) =>
        users.map((user) => user.displayName).join(', ');
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              DateFormat('EEEE d MMMM').format(day.date),
              style: textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            for (final slot in day.slots) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      slot.slot == AvailabilitySlot.allDay
                          ? 'Whole day'
                          : slotLabel(slot.slot),
                      style: textTheme.titleSmall,
                    ),
                  ),
                  Text(counts(slot), style: textTheme.bodySmall),
                ],
              ),
              if (slot.freeUsers.isNotEmpty)
                Text(
                  'Free: ${names(slot.freeUsers)}',
                  style: textTheme.bodyMedium,
                ),
              if (slot.maybeUsers.isNotEmpty)
                Text(
                  'Maybe: ${names(slot.maybeUsers)}',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onPlan,
              icon: const Icon(Icons.event_available),
              label: const Text('Plan it'),
            ),
          ],
        ),
      ),
    );
  }
}
