import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:friends/features/availability/domain/month_days.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// A month of square days in seven columns, Monday first, including the
/// neighbouring months' days that complete the first and last weeks
/// ([monthGridDays]). [cellBuilder] draws each day.
///
/// The cells fill the width, or the height when it is bounded and shorter.
///
/// With [onPaint], dragging across days reports each day entered (after
/// the first, reported by [onPaintStart]): "painting" several days at once.
/// Don't put a paintable grid in a vertical scroll view: the scroll view
/// would take the vertical drags.
///
/// [rowTrailing] adds a narrow column after each week (given its Monday).
class MonthGrid extends StatefulWidget {
  const new({
    required this.month,
    required this.cellBuilder,
    this.onTapDay,
    this.onPaintStart,
    this.onPaint,
    this.rowTrailing,
    super.key,
  });

  /// The width of the [rowTrailing] column.
  static const trailingWidth = 40.0;

  static const _labelHeight = 20.0;
  static const _gap = 4.0;

  final DateTime month;
  final Widget Function(BuildContext context, DateTime day) cellBuilder;
  final ValueChanged<DateTime>? onTapDay;
  final ValueChanged<DateTime>? onPaintStart;
  final ValueChanged<DateTime>? onPaint;
  final Widget Function(int row, DateTime monday)? rowTrailing;

  @override
  State<MonthGrid> createState() => _MonthGridState();
}

class _MonthGridState extends State<MonthGrid> {
  DateTime? _lastPainted;
  Offset? _lastPosition;
  bool _started = false;

  /// Reports [day] unless it was the last one: the first through
  /// [MonthGrid.onPaintStart], the next ones through [MonthGrid.onPaint].
  void _paintAt(DateTime? day) {
    if (day == null || day == _lastPainted) return;
    _lastPainted = day;
    if (_started) {
      widget.onPaint!(day);
    } else {
      _started = true;
      widget.onPaintStart?.call(day);
    }
  }

  static DateTime? _dayAt(Offset position, double cell, List<DateTime> days) {
    final column = (position.dx / cell).floor();
    final row = (position.dy / cell).floor();
    final index = row * 7 + column;
    if (column < 0 || column > 6 || row < 0 || index >= days.length) {
      return null;
    }
    return days[index];
  }

  @override
  Widget build(BuildContext context) {
    final days = monthGridDays(widget.month);
    final rows = days.length ~/ 7;
    final labels = DateFormat.E();
    final textTheme = Theme.of(context).textTheme;
    final trailing = widget.rowTrailing;
    final trailingWidth = trailing == null ? 0.0 : MonthGrid.trailingWidth;
    return LayoutBuilder(
      builder: (context, constraints) {
        var cell = (constraints.maxWidth - trailingWidth) / 7;
        if (constraints.maxHeight.isFinite) {
          final height =
              constraints.maxHeight - MonthGrid._labelHeight - MonthGrid._gap;
          cell = math.min(cell, height / rows);
        }
        cell = math.max(cell, 0);

        Widget grid = SizedBox(
          width: cell * 7,
          height: cell * rows,
          child: Column(
            children: [
              for (var row = 0; row < rows; row++)
                Row(
                  children: [
                    for (final day in days.skip(row * 7).take(7))
                      SizedBox(
                        width: cell,
                        height: cell,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onTapDay == null
                              ? null
                              : () => widget.onTapDay!(day),
                          child: widget.cellBuilder(context, day),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );
        if (widget.onPaint != null) {
          grid = GestureDetector(
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: (details) {
              _started = false;
              _lastPainted = null;
              _lastPosition = details.localPosition;
              _paintAt(_dayAt(details.localPosition, cell, days));
            },
            onPanUpdate: (details) {
              // Every day along the way: a fast drag moves several cells
              // between two pointer events.
              final to = details.localPosition;
              final from = _lastPosition ?? to;
              final steps = math.max(
                1,
                ((to - from).distance * 3 / cell).ceil(),
              );
              for (var step = 1; step <= steps; step++) {
                _paintAt(
                  _dayAt(Offset.lerp(from, to, step / steps)!, cell, days),
                );
              }
              _lastPosition = to;
            },
            onPanEnd: (_) {
              _lastPainted = null;
              _lastPosition = null;
            },
            child: grid,
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: MonthGrid._labelHeight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final day in days.take(7))
                    SizedBox(
                      width: cell,
                      child: Text(
                        labels.format(day).substring(0, 2),
                        textAlign: TextAlign.center,
                        style: textTheme.labelSmall,
                      ),
                    ),
                  SizedBox(width: trailingWidth),
                ],
              ),
            ),
            const SizedBox(height: MonthGrid._gap),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                grid,
                if (trailing != null)
                  SizedBox(
                    width: trailingWidth,
                    child: Column(
                      children: [
                        for (var row = 0; row < rows; row++)
                          SizedBox(
                            height: cell,
                            child: Center(child: trailing(row, days[row * 7])),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The month title with previous and next buttons.
class MonthHeader extends StatelessWidget {
  const new({
    required this.month,
    required this.onChanged,
    this.trailing,
    super.key,
  });

  final DateTime month;
  final ValueChanged<DateTime> onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
        ),
        Expanded(
          child: Text(
            DateFormat.yMMMM().format(month),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => onChanged(DateTime(month.year, month.month + 1)),
        ),
        ?trailing,
      ],
    );
  }
}
