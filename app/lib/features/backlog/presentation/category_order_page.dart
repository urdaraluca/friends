import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/theme/app_theme.dart';
import 'package:friends/features/backlog/data/backlog_controller.dart';
import 'package:friends/features/backlog/presentation/widgets/category_visuals.dart';
import 'package:friends/features/groups/presentation/widgets/group_themed.dart';
import 'package:material_ui/material_ui.dart';

/// A category in the order being edited.
typedef OrderedCategory = ({
  String id,
  String name,
  String? icon,
  String? color,
  int subcategories,
});

/// Opens the reorder page for [categories]: the top-level ones, or
/// [parent]'s subcategories.
Future<void> openCategoryOrder(
  BuildContext context, {
  required String groupId,
  required List<OrderedCategory> categories,
  CategoryNode? parent,
  List<CategoryNode> tree = const [],
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => GroupThemed(
        groupId: groupId,
        child: CategoryOrderPage(
          groupId: groupId,
          categories: categories,
          parent: parent,
          tree: tree,
        ),
      ),
    ),
  );
}

/// [node] as an [OrderedCategory].
OrderedCategory orderedNode(CategoryNode node) => (
  id: node.id,
  name: node.name,
  icon: node.icon,
  color: node.effectiveColor,
  subcategories: node.subcategories.length,
);

/// [category] (a subcategory) as an [OrderedCategory].
OrderedCategory orderedSub(Category category, CategoryNode parent) => (
  id: category.id,
  name: category.name,
  icon: category.icon ?? parent.icon,
  color: category.effectiveColor,
  subcategories: 0,
);

/// Drag categories into a new order (admins: the order is the whole
/// group's), then Save. From the top level, a category's own subcategories
/// open in a page of their own.
class CategoryOrderPage extends ConsumerStatefulWidget {
  const new({
    required this.groupId,
    required this.categories,
    this.parent,
    this.tree = const [],
    super.key,
  });

  final String groupId;
  final List<OrderedCategory> categories;

  /// Whose subcategories these are; null for the top level.
  final CategoryNode? parent;

  /// The whole tree, for opening a category's subcategories.
  final List<CategoryNode> tree;

  @override
  ConsumerState<CategoryOrderPage> createState() => _CategoryOrderPageState();
}

class _CategoryOrderPageState extends ConsumerState<CategoryOrderPage> {
  late final List<OrderedCategory> _order = [...widget.categories];
  bool _saving = false;

  bool get _changed {
    for (var i = 0; i < _order.length; i++) {
      if (_order[i].id != widget.categories[i].id) return true;
    }
    return false;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(backlogControllerProvider.notifier).reorderCategories(
        widget.groupId,
        [for (final category in _order) category.id],
        parentId: widget.parent?.id,
      );
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final parent = widget.parent;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          parent == null ? 'Reorder categories' : 'Reorder ${parent.name}',
        ),
        actions: [
          TextButton(
            onPressed: _changed && !_saving ? () => unawaited(_save()) : null,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Drag the handles to change the order everyone sees.'),
          ),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: _order.length,
              onReorderItem: (from, to) =>
                  setState(() => _order.insert(to, _order.removeAt(from))),
              itemBuilder: (context, index) {
                final category = _order[index];
                final node = widget.tree
                    .where((n) => n.id == category.id)
                    .firstOrNull;
                return ListTile(
                  key: ValueKey(category.id),
                  leading: CategoryIcon(
                    icon: category.icon,
                    color: HexColor.tryParse(category.color),
                  ),
                  title: Text(category.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (node != null && node.subcategories.length > 1)
                        IconButton(
                          tooltip: 'Reorder ${node.name}',
                          icon: const Icon(Icons.account_tree_outlined),
                          onPressed: () => unawaited(
                            openCategoryOrder(
                              context,
                              groupId: widget.groupId,
                              parent: node,
                              categories: [
                                for (final sub in node.subcategories)
                                  orderedSub(sub, node),
                              ],
                            ),
                          ),
                        ),
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.drag_handle,
                            key: ValueKey('drag-${category.id}'),
                            semanticLabel: 'Drag ${category.name}',
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
