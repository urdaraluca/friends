import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:friends/core/theme/app_theme.dart';
import 'package:friends/features/wheel/domain/wheel_math.dart';
import 'package:material_ui/material_ui.dart';

/// One slice of the wheel.
@immutable
class WheelSlice {
  const new({required this.label, this.color});

  final String label;

  /// `#RRGGBB`, or null for the fallback palette.
  final String? color;
}

/// Where the wheel must stop: slice [index], for the spin [spinId] (a new
/// ID starts a new animation).
@immutable
class WheelTarget {
  const new({required this.spinId, required this.index});

  final String spinId;
  final int index;
}

/// Colours for slices whose category has none.
const wheelPalette = [
  Color(0xFFEF6C00),
  Color(0xFF1565C0),
  Color(0xFF2E7D32),
  Color(0xFFAD1457),
  Color(0xFF6A1B9A),
  Color(0xFF00838F),
  Color(0xFFC62828),
  Color(0xFFF9A825),
];

/// Above this many slices the labels are hidden and a legend lists them.
const maxLabelledSlices = 24;

/// The animated wheel. It spins about 4.5 s (`easeOutQuart`) to [target]
/// and always stops on that slice (`WheelMath`); with animations disabled
/// (`MediaQuery.disableAnimations`) it jumps there at once.
class FortuneWheel extends StatefulWidget {
  const new({
    required this.slices,
    this.target,
    this.onSettled,
    this.size = 320,
    super.key,
  });

  final List<WheelSlice> slices;
  final WheelTarget? target;

  /// Called once the wheel stopped on [target].
  final VoidCallback? onSettled;
  final double size;

  static const spinDuration = Duration(milliseconds: 4500);

  @override
  State<FortuneWheel> createState() => _FortuneWheelState();
}

class _FortuneWheelState extends State<FortuneWheel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: FortuneWheel.spinDuration,
  )..addListener(_tick);
  Animation<double>? _animation;
  double _rotation = 0;
  int? _lastSlice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The first target (e.g. opening a finished spin) is shown at once.
    if (_animation == null && widget.target != null && _rotation == 0) {
      _jumpTo(widget.target!);
    }
  }

  @override
  void didUpdateWidget(FortuneWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.target;
    if (target != null && target.spinId != oldWidget.target?.spinId) {
      _spinTo(target);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _targetRotation(WheelTarget target) {
    final shape = WheelMath.spinShape(target.spinId.hashCode);
    return WheelMath.targetRotation(
      current: _rotation,
      index: target.index,
      count: widget.slices.length,
      turns: shape.turns,
      jitter: shape.jitter,
    );
  }

  void _jumpTo(WheelTarget target) {
    _rotation = _targetRotation(target) % WheelMath.fullTurn;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSettled?.call();
    });
  }

  void _spinTo(WheelTarget target) {
    if (widget.slices.isEmpty) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _jumpTo(target));
      return;
    }
    final end = _targetRotation(target);
    _animation = Tween<double>(
      begin: _rotation,
      end: end,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart));
    _controller
      ..reset()
      ..forward().whenCompleteOrCancel(() {
        if (mounted && _controller.isCompleted) widget.onSettled?.call();
      });
  }

  void _tick() {
    final animation = _animation;
    if (animation == null) return;
    setState(() => _rotation = animation.value);
    final slice = WheelMath.sliceAtPointer(_rotation, widget.slices.length);
    if (slice != _lastSlice) {
      _lastSlice = slice;
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        unawaited(HapticFeedback.selectionClick());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final slices = widget.slices;
    final colors = [
      for (final (index, slice) in slices.indexed)
        HexColor.tryParse(slice.color) ??
            wheelPalette[index % wheelPalette.length],
    ];
    final showLabels = slices.length <= maxLabelledSlices;
    final target = widget.target;
    final semantics = target != null && target.index < slices.length
        ? 'Wheel of ${slices.length} ideas; it picked '
              '${slices[target.index].label}'
        : 'Wheel of ${slices.length} ideas';
    final wheel = SizedBox.square(
      dimension: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: _rotation,
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: WheelPainter(
                labels: showLabels
                    ? [for (final slice in slices) slice.label]
                    : null,
                colors: colors,
                labelStyle: Theme.of(context).textTheme.labelMedium!,
                border: Theme.of(context).colorScheme.surface,
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: CustomPaint(
              size: const Size(28, 30),
              painter: _PointerPainter(Theme.of(context).colorScheme.onSurface),
            ),
          ),
          Container(
            width: widget.size * 0.12,
            height: widget.size * 0.12,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(blurRadius: 4, color: Colors.black26),
              ],
            ),
          ),
        ],
      ),
    );
    return Semantics(
      label: semantics,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(child: wheel),
          if (!showLabels) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final (index, slice) in slices.indexed)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colors[index],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(slice.label),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Paints the slices, clockwise from 12 o'clock, with optional labels along
/// each slice's radius.
class WheelPainter extends CustomPainter {
  const new({
    required this.colors,
    required this.labelStyle,
    required this.border,
    this.labels,
  });

  final List<Color> colors;
  final List<String>? labels;
  final TextStyle labelStyle;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final count = colors.length;
    if (count == 0) return;
    final radius = size.shortestSide / 2;
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = WheelMath.sliceAngle(count);
    // Canvas angles start at 3 o'clock; slices start at 12 o'clock.
    const top = -pi / 2;
    final fill = Paint()..style = PaintingStyle.fill;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = border;
    for (var i = 0; i < count; i++) {
      fill.color = colors[i];
      canvas
        ..drawArc(rect, top + i * sweep, sweep, true, fill)
        ..drawArc(rect, top + i * sweep, sweep, true, edge);
    }
    final labels = this.labels;
    if (labels == null) return;
    for (var i = 0; i < count; i++) {
      final background = colors[i];
      final color = background.computeLuminance() > 0.5
          ? Colors.black87
          : Colors.white;
      final painter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: labelStyle.copyWith(color: color),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: radius * 0.72);
      canvas
        ..save()
        ..translate(center.dx, center.dy)
        ..rotate(top + (i + 0.5) * sweep);
      painter.paint(canvas, Offset(radius * 0.2, -painter.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(WheelPainter oldDelegate) =>
      !listEquals(colors, oldDelegate.colors) ||
      !listEquals(labels, oldDelegate.labels) ||
      labelStyle != oldDelegate.labelStyle;
}

class _PointerPainter extends CustomPainter {
  const new(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas
      ..drawShadow(path, Colors.black, 2, false)
      ..drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PointerPainter oldDelegate) => color != oldDelegate.color;
}
