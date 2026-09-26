import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/date_only.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/theme/app_theme.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/features/backlog/presentation/widgets/category_visuals.dart';
import 'package:friends/features/groups/data/group_providers.dart';
import 'package:friends/features/recap/data/recap_providers.dart';
import 'package:friends/features/recap/domain/recap_period.dart';
import 'package:friends/features/recap/domain/recap_story.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// The story's background colours, one per card in turn.
const _palette = [
  Color(0xFF5E35B1),
  Color(0xFF00897B),
  Color(0xFFEF6C00),
  Color(0xFF3949AB),
  Color(0xFFC2185B),
  Color(0xFF2E7D32),
  Color(0xFF6D4C41),
];

/// `/groups/:groupId/recap?period=month|year&start=YYYY-MM-DD`: the group's
/// "Wrapped", one stat per card (contract section 14). Swipe or tap the
/// sides to move; share the card on screen as an image.
class RecapScreen extends ConsumerStatefulWidget {
  const new({
    required this.groupId,
    this.period = RecapPeriod.month,
    this.start,
    super.key,
  });

  final String groupId;
  final RecapPeriod period;

  /// The period's first day (`YYYY-MM-DD`), or null for the current one.
  final String? start;

  @override
  ConsumerState<RecapScreen> createState() => _RecapScreenState();
}

class _RecapScreenState extends ConsumerState<RecapScreen> {
  late RecapPeriod _period = widget.period;
  late String? _start = widget.start;
  final _pages = PageController();
  final _cardKeys = <int, GlobalKey>{};
  int _page = 0;
  bool _sharing = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _show(RecapPeriod period, String? start) {
    setState(() {
      _period = period;
      _start = start;
      _page = 0;
    });
    if (_pages.hasClients) _pages.jumpToPage(0);
  }

  void _goTo(int page, int count) {
    if (page < 0 || page >= count) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(
        page,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _share(Recap recap, String groupName) async {
    final boundary = _cardKeys[_page]?.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return;
    setState(() => _sharing = true);
    try {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) return;
      final start = DateOnly.from(recap.start);
      final label = periodLabel(
        recap.period,
        DateTime(start.year, start.month),
      );
      await ref
          .read(recapSharerProvider)
          .shareImage(
            bytes.buffer.asUint8List(),
            text: 'Our $label with $groupName, on Friends',
          );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't share the recap.")),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = groupRecapProvider(widget.groupId, _period, _start);
    final recap = ref.watch(provider);
    final groupName =
        ref.watch(groupProvider(widget.groupId)).value?.name ?? 'your group';
    final loaded = recap.value;
    return Scaffold(
      appBar: AppBar(
        // Opened from a link: back goes to the group.
        leading: context.canPop()
            ? null
            : IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go(Routes.groupHub(widget.groupId)),
              ),
        title: const Text('Recap'),
        actions: [
          IconButton(
            tooltip: 'Share this card',
            icon: _sharing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share),
            onPressed: loaded == null || _sharing
                ? null
                : () => unawaited(_share(loaded, groupName)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _PeriodBar(period: _period, recap: loaded, onChanged: _show),
            Expanded(
              child: AsyncValueView(
                value: recap,
                onRetry: () => ref.invalidate(provider),
                data: (recap) {
                  final cards = recapStory(recap, groupName: groupName);
                  final page = _page.clamp(0, cards.length - 1);
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Row(
                          children: [
                            for (var i = 0; i < cards.length; i++)
                              Expanded(
                                child: Container(
                                  height: 3,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: i <= page
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) => GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTapUp: (details) => _goTo(
                              details.localPosition.dx <
                                      constraints.maxWidth / 3
                                  ? page - 1
                                  : page + 1,
                              cards.length,
                            ),
                            child: PageView.builder(
                              controller: _pages,
                              itemCount: cards.length,
                              onPageChanged: (index) =>
                                  setState(() => _page = index),
                              itemBuilder: (context, index) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 440,
                                    ),
                                    child: AspectRatio(
                                      aspectRatio: 9 / 14,
                                      child: RepaintBoundary(
                                        key: _cardKeys.putIfAbsent(
                                          index,
                                          GlobalKey.new,
                                        ),
                                        child: RecapCardView(
                                          card: cards[index],
                                          background:
                                              HexColor.tryParse(
                                                cards[index].color,
                                              ) ??
                                              _palette[index % _palette.length],
                                          groupName: groupName,
                                          onOpenActivity: (id) => unawaited(
                                            context.push(
                                              Routes.activity(
                                                widget.groupId,
                                                id,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              tooltip: 'Previous card',
                              icon: const Icon(Icons.arrow_back),
                              onPressed: page == 0
                                  ? null
                                  : () => _goTo(page - 1, cards.length),
                            ),
                            Text('${page + 1} / ${cards.length}'),
                            IconButton(
                              tooltip: 'Next card',
                              icon: const Icon(Icons.arrow_forward),
                              onPressed: page == cards.length - 1
                                  ? null
                                  : () => _goTo(page + 1, cards.length),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Month or year, and the period before or after the one shown.
class _PeriodBar extends StatelessWidget {
  const new({
    required this.period,
    required this.recap,
    required this.onChanged,
  });

  final RecapPeriod period;

  /// The recap shown, once loaded: its `start` is the period's.
  final Recap? recap;
  final void Function(RecapPeriod period, String? start) onChanged;

  @override
  Widget build(BuildContext context) {
    final recap = this.recap;
    final start = recap == null ? null : DateOnly.from(recap.start);
    final local = start == null ? null : DateTime(start.year, start.month);
    final year = period == RecapPeriod.year;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Column(
        children: [
          SegmentedButton<RecapPeriod>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: RecapPeriod.month, label: Text('Month')),
              ButtonSegment(value: RecapPeriod.year, label: Text('Year')),
            ],
            selected: {period},
            onSelectionChanged: (selection) {
              final next = selection.first;
              if (local == null || recap == null) {
                onChanged(next, null);
                return;
              }
              onChanged(next, switch (next) {
                // The year of the month shown.
                RecapPeriod.year => DateOnly.format(DateTime(local.year)),
                // December of a past year, else the current month.
                _ =>
                  recap.complete
                      ? DateOnly.format(DateTime(local.year, 12))
                      : null,
              });
            },
          ),
          Row(
            children: [
              IconButton(
                tooltip: year ? 'Previous year' : 'Previous month',
                icon: const Icon(Icons.chevron_left),
                onPressed: local == null
                    ? null
                    : () => onChanged(
                        period,
                        DateOnly.format(shiftPeriod(period, local, -1)),
                      ),
              ),
              Expanded(
                child: Text(
                  local == null ? '' : periodLabel(period, local),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: year ? 'Next year' : 'Next month',
                icon: const Icon(Icons.chevron_right),
                // The current period is the latest one.
                onPressed: local == null || recap == null || !recap.complete
                    ? null
                    : () => onChanged(
                        period,
                        DateOnly.format(shiftPeriod(period, local, 1)),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One card of the story.
class RecapCardView extends StatelessWidget {
  const new({
    required this.card,
    required this.background,
    required this.groupName,
    required this.onOpenActivity,
    super.key,
  });

  final RecapCard card;
  final Color background;
  final String groupName;
  final ValueChanged<String> onOpenActivity;

  @override
  Widget build(BuildContext context) {
    final foreground =
        ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final headlineStyle =
        (card.number != null ? textTheme.displayLarge : textTheme.headlineLarge)
            ?.copyWith(color: foreground, fontWeight: FontWeight.w800);
    final number = card.number;
    final activityId = card.activityId;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: ColoredBox(
        color: background,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text(
                card.eyebrow.toUpperCase(),
                style: textTheme.labelLarge?.copyWith(
                  color: foreground.withValues(alpha: 0.85),
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              if (number != null && !reduceMotion)
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: number.toDouble()),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) =>
                      Text('${value.round()}', style: headlineStyle),
                )
              else
                Text(
                  card.headline,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: headlineStyle,
                ),
              if (card.subtitle case final subtitle?) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: textTheme.titleMedium?.copyWith(color: foreground),
                ),
              ],
              if (card.lines.isNotEmpty) const SizedBox(height: 20),
              for (final line in card.lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      if (line.color != null) ...[
                        DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: foreground, width: 1.5),
                          ),
                          child: ColorDot(color: line.color, size: 12),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          line.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyLarge?.copyWith(
                            color: foreground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (activityId != null) ...[
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => onOpenActivity(activityId),
                  child: const Text('Open'),
                ),
              ],
              const Spacer(),
              Text(
                'Friends · $groupName',
                style: textTheme.labelMedium?.copyWith(
                  color: foreground.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
