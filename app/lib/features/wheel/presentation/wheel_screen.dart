import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/date_only.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/features/backlog/data/backlog_providers.dart';
import 'package:friends/features/backlog/domain/activity_rules.dart';
import 'package:friends/features/backlog/domain/category_index.dart';
import 'package:friends/features/backlog/presentation/widgets/backlog_filter_bar.dart';
import 'package:friends/features/backlog/presentation/widgets/category_picker.dart';
import 'package:friends/features/backlog/presentation/widgets/category_visuals.dart';
import 'package:friends/features/groups/data/group_providers.dart';
import 'package:friends/features/wheel/data/wheel_providers.dart';
import 'package:friends/features/wheel/presentation/fortune_wheel.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// Candidates per spin (contract section 1.9).
const minWheelCandidates = 2;
const maxWheelCandidates = 50;

/// Messages for wheel errors.
const Map<String, String> wheelErrorMessages = {
  ErrorCodes.notEnoughCandidates: 'Add at least 2 ideas to spin.',
  ErrorCodes.resultDeleted: 'That idea was deleted in the meantime.',
};

/// The Wheel tab (`/groups/:groupId/wheel`): filters, the candidates (all
/// on by default; uncheck some to hand-pick), the wheel, and the result.
///
/// The server picks the result; the wheel then shows the spin's slices in
/// the server's order and turns to its `result_index` (contract section 10).
class WheelScreen extends ConsumerStatefulWidget {
  const new({required this.groupId, super.key});

  final String groupId;

  @override
  ConsumerState<WheelScreen> createState() => _WheelScreenState();
}

class _WheelScreenState extends ConsumerState<WheelScreen> {
  /// Candidates the user unchecked.
  final Set<String> _excluded = {};
  WheelSpin? _spin;
  bool _settled = false;
  bool _spinning = false;
  bool _accepting = false;
  String? _error;

  String get _groupId => widget.groupId;

  WheelFilters get _filters => ref.read(wheelFilterProvider(_groupId));

  void _setFilters(WheelFilters filters) {
    ref.read(wheelFilterProvider(_groupId).notifier).set(filters);
    setState(() {
      _excluded.clear();
      _spin = null;
      _error = null;
    });
  }

  Future<void> _spinWheel(List<ActivitySummary> checked) async {
    setState(() {
      _spinning = true;
      _error = null;
    });
    try {
      final spin = await ref
          .read(wheelControllerProvider.notifier)
          .spin(
            _groupId,
            SpinCreate(
              filters: _filters,
              activityIds: _excluded.isEmpty
                  ? null
                  : [for (final activity in checked) activity.id],
            ),
          );
      if (!mounted) return;
      setState(() {
        _spin = spin;
        _settled = false;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(
          () => _error = friendlyErrorMessage(
            error,
            messages: wheelErrorMessages,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _spinning = false);
    }
  }

  Future<void> _accept(WheelSpin spin) async {
    setState(() {
      _accepting = true;
      _error = null;
    });
    try {
      final accepted = await ref
          .read(wheelControllerProvider.notifier)
          .accept(spin);
      if (mounted) setState(() => _spin = accepted);
    } on ApiException catch (error) {
      if (mounted) {
        setState(
          () => _error = friendlyErrorMessage(
            error,
            messages: wheelErrorMessages,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(wheelFilterProvider(_groupId));
    final categories =
        ref.watch(categoryIndexProvider(_groupId)).value ??
        CategoryIndex.empty();
    final candidates = ref.watch(wheelCandidatesProvider(_groupId, filters));
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _WheelFilterBar(
          groupId: _groupId,
          filters: filters,
          categories: categories,
          onChanged: _setFilters,
        ),
        AsyncValueView(
          value: candidates,
          onRetry: () =>
              ref.invalidate(wheelCandidatesProvider(_groupId, filters)),
          loading: const Padding(
            padding: EdgeInsets.all(48),
            child: LoadingView(),
          ),
          data: (pool) => _body(context, pool, categories),
        ),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    WheelCandidates pool,
    CategoryIndex categories,
  ) {
    final checked = [
      for (final activity in pool.items)
        if (!_excluded.contains(activity.id)) activity,
    ];
    final spin = _spin;
    final slices = spin != null
        ? [
            for (final candidate in spin.candidates)
              WheelSlice(label: candidate.title, color: candidate.color),
          ]
        : [
            for (final activity in checked)
              WheelSlice(
                label: activity.title,
                color: categories.color(activity.categoryId),
              ),
          ];
    final canSpin =
        checked.length >= minWheelCandidates && !_spinning && _spinningDone;
    final textTheme = Theme.of(context).textTheme;
    final summary = pool.total == 0
        ? 'No ideas match these filters.'
        : pool.total > pool.items.length
        ? 'Showing ${pool.items.length} of ${pool.total} ideas'
        : '${pool.total} ${pool.total == 1 ? 'idea' : 'ideas'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExpansionTile(
          title: Text(summary),
          subtitle: _excluded.isEmpty
              ? const Text('All on the wheel. Open to hand-pick.')
              : Text('${checked.length} on the wheel'),
          children: [
            for (final activity in pool.items)
              CheckboxListTile(
                dense: true,
                value: !_excluded.contains(activity.id),
                onChanged: _spinning
                    ? null
                    : (on) => setState(() {
                        if (on ?? false) {
                          _excluded.remove(activity.id);
                        } else {
                          _excluded.add(activity.id);
                        }
                        _spin = null;
                      }),
                title: Text(activity.title),
                subtitle: CategoryLabel(
                  index: categories,
                  categoryId: activity.categoryId,
                  style: textTheme.bodySmall,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Center(
          child: slices.isEmpty
              ? const SizedBox(
                  height: 120,
                  child: Center(child: Icon(Icons.casino_outlined, size: 64)),
                )
              : LayoutBuilder(
                  builder: (context, constraints) => FortuneWheel(
                    slices: slices,
                    size: constraints.maxWidth.clamp(200, 360) - 32,
                    target: spin == null
                        ? null
                        : WheelTarget(spinId: spin.id, index: spin.resultIndex),
                    onSettled: () {
                      if (mounted) setState(() => _settled = true);
                    },
                  ),
                ),
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.icon(
            onPressed: canSpin ? () => unawaited(_spinWheel(checked)) : null,
            icon: _spinning
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.casino),
            label: Text(spin == null ? 'Spin!' : 'Spin again'),
          ),
        ),
        if (checked.length < minWheelCandidates)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Add at least 2 ideas to spin',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
            ),
          ),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (spin != null && _settled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SpinResultCard(
              groupId: _groupId,
              spin: spin,
              accepting: _accepting,
              onAccept: () => unawaited(_accept(spin)),
            ),
          ),
      ],
    );
  }

  /// A spin's animation has finished (or there is no spin).
  bool get _spinningDone => _spin == null || _settled;
}

/// What the wheel picked: "Let's do it!" (accept: an idea becomes
/// planning), then "Schedule it"; "Open activity".
class SpinResultCard extends ConsumerWidget {
  const new({
    required this.groupId,
    required this.spin,
    required this.accepting,
    required this.onAccept,
    super.key,
  });

  final String groupId;
  final WheelSpin spin;
  final bool accepting;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final result = spin.result;
    final activityId = spin.resultActivityId;
    final me = ref.watch(currentUserIdProvider);
    final acceptedBy = spin.acceptedBy;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('The wheel says…', style: textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                ColorDot(color: result.color, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(result.title, style: textTheme.headlineSmall),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (activityId == null)
              const Text('This idea has been deleted since.')
            else if (spin.acceptedAt != null)
              Text(
                acceptedBy == null
                    ? "It's on!"
                    : acceptedBy.id == me
                    ? "You said let's do it."
                    : "${acceptedBy.displayName} said let's do it.",
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (activityId != null && spin.acceptedAt == null)
                  FilledButton.icon(
                    onPressed: accepting ? null : onAccept,
                    icon: const Icon(Icons.celebration),
                    label: const Text("Let's do it!"),
                  ),
                if (activityId != null && spin.acceptedAt != null)
                  FilledButton.icon(
                    onPressed: () => unawaited(
                      context.push(
                        Routes.newEvent(groupId, activityId: activityId),
                      ),
                    ),
                    icon: const Icon(Icons.event_available),
                    label: const Text('Schedule it'),
                  ),
                if (activityId != null)
                  OutlinedButton(
                    onPressed: () => unawaited(
                      context.push(Routes.activity(groupId, activityId)),
                    ),
                    child: const Text('Open activity'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WheelFilterBar extends ConsumerWidget {
  const new({
    required this.groupId,
    required this.filters,
    required this.categories,
    required this.onChanged,
  });

  final String groupId;
  final WheelFilters filters;
  final CategoryIndex categories;
  final ValueChanged<WheelFilters> onChanged;

  List<ActivityStatus> get _statuses => filters.status ?? wheelDefaultStatuses;

  void _toggle(ActivityStatus status, {required bool on}) {
    final next = {..._statuses};
    if (on) {
      next.add(status);
    } else if (next.length > 1) {
      next.remove(status);
    }
    onChanged(
      filters.copyWith(
        status: [
          for (final s in ActivityStatus.$valuesDefined)
            if (next.contains(s)) s,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    final due = filters.dueBefore;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          for (final status in wheelDefaultStatuses) ...[
            FilterChip(
              label: Text(status.label),
              selected: _statuses.contains(status),
              onSelected: (on) => _toggle(status, on: on),
            ),
            const SizedBox(width: 6),
          ],
          FilterChip(
            label: const Text("Only ideas I'm interested in"),
            selected: filters.interestedBy != null,
            onSelected: (on) =>
                onChanged(filters.copyWith(interestedBy: on ? me : null)),
          ),
          const SizedBox(width: 6),
          InputChip(
            avatar: const Icon(Icons.category_outlined, size: 18),
            label: Text(categories.name(filters.categoryId) ?? 'Category'),
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
                onChanged(
                  filters.copyWith(
                    categoryId: choice.id,
                    includeSubcategories: true,
                  ),
                );
              }
            },
            onDeleted: filters.categoryId == null
                ? null
                : () => onChanged(filters.copyWith(categoryId: null)),
          ),
          const SizedBox(width: 6),
          InputChip(
            avatar: const Icon(Icons.payments_outlined, size: 18),
            label: Text(
              filters.costMax == null ? 'Max cost' : 'Up to ${filters.costMax}',
            ),
            selected: filters.costMax != null,
            showCheckmark: false,
            onPressed: () async {
              final currency = ref.read(groupProvider(groupId)).value?.currency;
              final result = await showDialog<CostFilter>(
                context: context,
                builder: (context) => CostFilterDialog(
                  costMax: filters.costMax,
                  includeUnpriced: filters.includeUnpriced,
                  currency: currency,
                ),
              );
              if (result != null) {
                onChanged(
                  filters.copyWith(
                    costMax: result.costMax,
                    includeUnpriced: result.includeUnpriced,
                  ),
                );
              }
            },
            onDeleted: filters.costMax == null
                ? null
                : () => onChanged(filters.copyWith(costMax: null)),
          ),
          const SizedBox(width: 6),
          InputChip(
            avatar: const Icon(Icons.flag_outlined, size: 18),
            label: Text(
              due == null
                  ? 'Due before'
                  : 'By ${DateFormat.MMMd().format(due)}',
            ),
            selected: due != null,
            showCheckmark: false,
            onPressed: () async {
              final today = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: due == null
                    ? today
                    : DateTime(due.year, due.month, due.day),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                onChanged(filters.copyWith(dueBefore: DateOnly.from(picked)));
              }
            },
            onDeleted: due == null
                ? null
                : () => onChanged(filters.copyWith(dueBefore: null)),
          ),
          const SizedBox(width: 6),
          ActionChip(
            avatar: const Icon(Icons.history, size: 18),
            label: const Text('History'),
            onPressed: () =>
                unawaited(context.push(Routes.wheelHistory(groupId))),
          ),
        ],
      ),
    );
  }
}
