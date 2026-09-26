import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/features/backlog/domain/activity_filter.dart';
import 'package:friends/features/backlog/domain/activity_rules.dart';
import 'package:friends/features/backlog/domain/category_index.dart';
import 'package:friends/features/backlog/presentation/widgets/category_picker.dart';
import 'package:friends/features/groups/data/group_providers.dart';
import 'package:material_ui/material_ui.dart';

/// The backlog's search field, filter chips and sort menu.
class BacklogFilterBar extends ConsumerStatefulWidget {
  const new({
    required this.groupId,
    required this.filter,
    required this.categories,
    required this.onChanged,
    super.key,
  });

  final String groupId;
  final ActivityFilter filter;
  final CategoryIndex categories;
  final ValueChanged<ActivityFilter> onChanged;

  /// How long typing pauses before the search runs.
  static const searchDebounce = Duration(milliseconds: 300);

  @override
  ConsumerState<BacklogFilterBar> createState() => _BacklogFilterBarState();
}

class _BacklogFilterBarState extends ConsumerState<BacklogFilterBar> {
  late final _search = TextEditingController(text: widget.filter.query);
  Timer? _debounce;

  @override
  void didUpdateWidget(BacklogFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // "Clear filters" resets the query from outside.
    if (widget.filter.query != _search.text && _debounce?.isActive != true) {
      _search.text = widget.filter.query;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _searchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(BacklogFilterBar.searchDebounce, () {
      if (mounted && text != widget.filter.query) {
        widget.onChanged(widget.filter.copyWith(query: text));
      }
    });
    setState(() {}); // the clear button
  }

  void _toggleStatus(ActivityStatus status, {required bool on}) {
    final statuses = {...widget.filter.statuses};
    if (on) {
      statuses.add(status);
    } else {
      // Keep at least one status: none would mean the server's default.
      if (statuses.length == 1 && !widget.filter.showArchived) return;
      statuses.remove(status);
    }
    widget.onChanged(widget.filter.copyWith(statuses: statuses));
  }

  Future<void> _pickCategory() async {
    final choice = await showCategoryPicker(
      context,
      index: widget.categories,
      selectedId: widget.filter.categoryId,
      noneLabel: 'All categories',
    );
    if (choice is PickedCategory) {
      widget.onChanged(
        widget.filter.copyWith(
          categoryId: () => choice.id,
          includeSubcategories: true,
        ),
      );
    }
  }

  Future<void> _pickCost() async {
    final currency = ref.read(groupProvider(widget.groupId)).value?.currency;
    final result = await showDialog<CostFilter>(
      context: context,
      builder: (context) => CostFilterDialog(
        costMax: widget.filter.costMax,
        includeUnpriced: widget.filter.includeUnpriced,
        currency: currency,
      ),
    );
    if (result == null) return;
    widget.onChanged(
      widget.filter.copyWith(
        costMax: () => result.costMax,
        includeUnpriced: result.includeUnpriced,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter = widget.filter;
    final categoryName = widget.categories.name(filter.categoryId);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: _searchChanged,
                    textInputAction: TextInputAction.search,
                    inputFormatters: [LengthLimitingTextInputFormatter(100)],
                    decoration: InputDecoration(
                      hintText: 'Search ideas',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _search.clear();
                                _debounce?.cancel();
                                widget.onChanged(filter.copyWith(query: ''));
                                setState(() {});
                              },
                            ),
                    ),
                  ),
                ),
                _SortMenu(filter: filter, onChanged: widget.onChanged),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                for (final status in ActivityFilter.activeStatuses) ...[
                  FilterChip(
                    label: Text(status.label),
                    selected: filter.statuses.contains(status),
                    onSelected: (on) => _toggleStatus(status, on: on),
                  ),
                  const SizedBox(width: 6),
                ],
                FilterChip(
                  label: const Text('Show archived'),
                  selected: filter.showArchived,
                  onSelected: (on) {
                    // Turning the archive off with no active status left
                    // would mean "everything active" (the server's default).
                    final statuses = !on && filter.statuses.isEmpty
                        ? ActivityFilter.activeStatuses
                        : filter.statuses;
                    widget.onChanged(
                      filter.copyWith(showArchived: on, statuses: statuses),
                    );
                  },
                ),
                const SizedBox(width: 6),
                InputChip(
                  avatar: const Icon(Icons.category_outlined, size: 18),
                  label: Text(categoryName ?? 'Category'),
                  selected: filter.categoryId != null,
                  showCheckmark: false,
                  onPressed: () => unawaited(_pickCategory()),
                  onDeleted: filter.categoryId == null
                      ? null
                      : () => widget.onChanged(
                          filter.copyWith(categoryId: () => null),
                        ),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: const Text("I'm interested"),
                  selected: filter.onlyInterested,
                  onSelected: (on) =>
                      widget.onChanged(filter.copyWith(onlyInterested: on)),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: const Text('Mine'),
                  selected: filter.onlyMine,
                  onSelected: (on) =>
                      widget.onChanged(filter.copyWith(onlyMine: on)),
                ),
                const SizedBox(width: 6),
                InputChip(
                  avatar: const Icon(Icons.payments_outlined, size: 18),
                  label: Text(
                    filter.costMax == null
                        ? 'Max cost'
                        : 'Up to ${filter.costMax}',
                  ),
                  selected: filter.costMax != null,
                  showCheckmark: false,
                  onPressed: () => unawaited(_pickCost()),
                  onDeleted: filter.costMax == null
                      ? null
                      : () => widget.onChanged(
                          filter.copyWith(costMax: () => null),
                        ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  const new({required this.filter, required this.onChanged});

  final ActivityFilter filter;
  final ValueChanged<ActivityFilter> onChanged;

  static const Map<ActivitySort, String> _labels = {
    ActivitySort.createdAt: 'Newest',
    ActivitySort.dueDate: 'Due date',
    ActivitySort.title: 'Title',
    ActivitySort.interestCount: 'Most interest',
    ActivitySort.estimatedCost: 'Cost',
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: 'Sort',
      icon: const Icon(Icons.sort),
      onSelected: (value) => switch (value) {
        final ActivitySort sort => onChanged(filter.copyWith(sort: sort)),
        final SortOrder order => onChanged(filter.copyWith(order: order)),
        _ => null,
      },
      itemBuilder: (context) => [
        for (final MapEntry(key: sort, value: label) in _labels.entries)
          CheckedPopupMenuItem<Object>(
            value: sort,
            checked: filter.sort == sort,
            child: Text(label),
          ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem<Object>(
          value: SortOrder.asc,
          checked: filter.order == SortOrder.asc,
          child: const Text('Ascending'),
        ),
        CheckedPopupMenuItem<Object>(
          value: SortOrder.desc,
          checked: filter.order == SortOrder.desc,
          child: const Text('Descending'),
        ),
      ],
    );
  }
}

/// The max-cost filter chosen in [CostFilterDialog].
class CostFilter {
  const new(this.costMax, {required this.includeUnpriced});

  final int? costMax;
  final bool includeUnpriced;
}

/// Asks for a maximum cost (in the group currency) and whether to include
/// ideas without one. Pops a [CostFilter]; "Clear" pops one without a max.
class CostFilterDialog extends StatefulWidget {
  const new({
    required this.costMax,
    required this.includeUnpriced,
    required this.currency,
    super.key,
  });

  final int? costMax;
  final bool includeUnpriced;
  final String? currency;

  @override
  State<CostFilterDialog> createState() => _CostFilterDialogState();
}

class _CostFilterDialogState extends State<CostFilterDialog> {
  late final _amount = TextEditingController(
    text: widget.costMax?.toString() ?? '',
  );
  late bool _includeUnpriced = widget.includeUnpriced;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Max cost'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            decoration: InputDecoration(
              labelText: 'At most',
              suffixText: widget.currency,
              helperText: 'In the group currency',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Include ideas without a cost'),
            value: _includeUnpriced,
            onChanged: (value) => setState(() => _includeUnpriced = value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context)
                  .pop(const CostFilter(null, includeUnpriced: true)),
          child: const Text('Clear'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            CostFilter(
              int.tryParse(_amount.text),
              includeUnpriced: _includeUnpriced,
            ),
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
