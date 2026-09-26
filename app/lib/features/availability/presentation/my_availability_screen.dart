import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/date_only.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/features/availability/data/availability_providers.dart';
import 'package:friends/features/availability/domain/availability_draft.dart';
import 'package:friends/features/availability/domain/month_days.dart';
import 'package:friends/features/availability/presentation/widgets/availability_style.dart';
import 'package:friends/features/availability/presentation/widgets/month_grid.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

enum _Unsaved { save, discard }

/// `/availability?month=YYYY-MM-DD`: when I'm free, a month at a time
/// (contract section 13). One answer shows in every group I'm in.
///
/// Tapping a day cycles the selected slot through free, maybe, busy and not
/// set; dragging paints the tapped day's new answer over the days crossed.
/// Nothing is sent until Save.
class MyAvailabilityScreen extends ConsumerStatefulWidget {
  const new({this.initialMonth, super.key});

  /// A day of the month to open on, else this month.
  final DateTime? initialMonth;

  @override
  ConsumerState<MyAvailabilityScreen> createState() =>
      _MyAvailabilityScreenState();
}

class _MyAvailabilityScreenState extends ConsumerState<MyAvailabilityScreen> {
  late DateTime _month = _firstOf(widget.initialMonth ?? DateTime.now());
  AvailabilitySlot _slot = AvailabilitySlot.allDay;

  /// The answers being edited, from the month's saved ones.
  AvailabilityDraft? _draft;

  /// What a drag paints: the first day's new answer.
  AvailabilityStatus? _paint;
  bool _saving = false;

  static DateTime _firstOf(DateTime day) => DateTime(day.year, day.month);

  bool get _dirty => _draft?.dirty ?? false;

  void _edit(void Function(AvailabilityDraft draft) change) {
    final draft = _draft;
    if (draft == null || _saving) return;
    setState(() => change(draft));
  }

  void _cycle(DateTime day) => _edit(
    (draft) =>
        draft.set(day, _slot, AvailabilityDraft.next(draft.status(day, _slot))),
  );

  void _paintStart(DateTime day) => _edit((draft) {
    _paint = AvailabilityDraft.next(draft.status(day, _slot));
    draft.set(day, _slot, _paint);
  });

  void _paintDay(DateTime day) =>
      _edit((draft) => draft.set(day, _slot, _paint));

  void _copyWeekAbove(DateTime monday) => _edit(
    (draft) => draft.copyWeek(
      DateTime(monday.year, monday.month, monday.day - 7),
      monday,
    ),
  );

  Future<bool> _save() async {
    final draft = _draft;
    if (draft == null) return true;
    final range = gridRange(_month);
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(availabilityControllerProvider.notifier)
          .saveMonth(_month, draft.entries(range.from, range.to));
      if (!mounted) return true;
      setState(() => _draft = AvailabilityDraft(saved.entries));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Availability saved.')));
      return true;
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Whether the edits are saved or discarded (asking which), so the month
  /// can change or the screen close.
  Future<bool> _resolveUnsaved() async {
    if (!_dirty) return true;
    final choice = await showDialog<_Unsaved>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save your changes?'),
        content: Text(
          'Your availability for ${DateFormat.yMMMM().format(_month)} '
          "isn't saved yet.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_Unsaved.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_Unsaved.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return switch (choice) {
      null => false,
      _Unsaved.discard => true,
      _Unsaved.save => await _save(),
    };
  }

  Future<void> _changeMonth(DateTime month) async {
    if (!await _resolveUnsaved() || !mounted) return;
    setState(() {
      _month = month;
      _draft = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(myAvailabilityProvider(_month));
    if (saved.value case final value? when _draft == null) {
      _draft = AvailabilityDraft(value.entries);
    }
    final draft = _draft;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _resolveUnsaved() && context.mounted) {
          setState(() => _draft = null);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          // Opened directly (a deep link): nothing to pop.
          leading: context.canPop()
              ? null
              : IconButton(
                  tooltip: 'Home',
                  icon: const Icon(Icons.home_outlined),
                  onPressed: () => context.go(Routes.home),
                ),
          title: const Text('My availability'),
          actions: [
            TextButton(
              onPressed: _dirty && !_saving ? () => unawaited(_save()) : null,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                children: [
                  MonthHeader(
                    month: _month,
                    onChanged: (month) => unawaited(_changeMonth(month)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: SlotChips(
                      selected: _slot,
                      onSelected: (slot) => setState(() => _slot = slot),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: draft == null
                        ? AsyncValueView(
                            value: saved,
                            onRetry: () =>
                                ref.invalidate(myAvailabilityProvider(_month)),
                            data: (_) => const LoadingView(),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: MonthGrid(
                              month: _month,
                              cellBuilder: (context, day) => _DayCell(
                                day: day,
                                month: _month,
                                slot: _slot,
                                draft: draft,
                              ),
                              onTapDay: _cycle,
                              onPaintStart: _paintStart,
                              onPaint: _paintDay,
                              rowTrailing: (row, monday) => row == 0
                                  ? const SizedBox.shrink()
                                  : IconButton(
                                      key: ValueKey(
                                        'copy-week-${DateOnly.format(monday)}',
                                      ),
                                      tooltip: 'Copy last week',
                                      iconSize: 18,
                                      icon: const Icon(Icons.content_copy),
                                      onPressed: () => _copyWeekAbove(monday),
                                    ),
                            ),
                          ),
                  ),
                  const _Legend(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A day of the editor: coloured by its answer for the selected slot. An
/// answer inherited from the whole day is paler; on the whole day, answers
/// for its parts show as three bars.
class _DayCell extends StatelessWidget {
  const new({
    required this.day,
    required this.month,
    required this.slot,
    required this.draft,
  });

  final DateTime day;
  final DateTime month;
  final AvailabilitySlot slot;
  final AvailabilityDraft draft;

  static const List<AvailabilitySlot> _parts = [
    AvailabilitySlot.morning,
    AvailabilitySlot.afternoon,
    AvailabilitySlot.evening,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final own = draft.status(day, slot);
    final shown = draft.effective(day, slot);
    final parts = slot == AvailabilitySlot.allDay && own == null
        ? [for (final part in _parts) draft.status(day, part)]
        : const <AvailabilityStatus?>[];
    final background = shown == null
        ? colors.surfaceContainerHighest
        : statusColor(shown).withValues(alpha: own == null ? 0.45 : 1);
    final outside = day.month != month.month;
    final today = DateOnly.isSameDay(day, DateTime.now());
    final label =
        '${DateFormat('EEEE d MMMM').format(day)}, '
        '${slotLabel(slot).toLowerCase()}: ${statusLabel(shown)}';
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: DecoratedBox(
          key: ValueKey('day-${DateOnly.format(day)}'),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: today ? Border.all(color: colors.primary, width: 2) : null,
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    color: shown == null
                        ? (outside ? colors.outline : colors.onSurface)
                        : onColor(statusColor(shown)),
                    fontWeight: outside ? FontWeight.normal : FontWeight.w600,
                  ),
                ),
              ),
              if (parts.any((part) => part != null))
                Positioned(
                  left: 6,
                  right: 6,
                  bottom: 5,
                  child: Row(
                    children: [
                      for (final part in parts)
                        Expanded(
                          child: Container(
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: part == null
                                  ? colors.outlineVariant
                                  : statusColor(part),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    Widget swatch(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: textTheme.bodySmall),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              for (final status in [
                AvailabilityStatus.free,
                AvailabilityStatus.maybe,
                AvailabilityStatus.busy,
              ])
                swatch(statusColor(status), statusLabel(status)),
              swatch(colors.surfaceContainerHighest, statusLabel(null)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Tap a day to switch between free, maybe, busy and not set; '
            'drag to fill several days. Every group you are in sees it.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
