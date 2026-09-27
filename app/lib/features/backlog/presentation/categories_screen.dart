import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/theme/app_theme.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/core/widgets/confirm_dialog.dart';
import 'package:friends/features/backlog/data/backlog_controller.dart';
import 'package:friends/features/backlog/data/backlog_providers.dart';
import 'package:friends/features/backlog/domain/category_index.dart';
import 'package:friends/features/backlog/presentation/category_form_page.dart';
import 'package:friends/features/backlog/presentation/category_order_page.dart';
import 'package:friends/features/backlog/presentation/widgets/category_visuals.dart';
import 'package:friends/features/groups/data/group_providers.dart';
import 'package:friends/features/groups/presentation/widgets/group_themed.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// A group's categories (`/groups/:groupId/settings/categories`): top-level
/// ones in order, each expandable to its subcategories, with add, edit and
/// delete where allowed (`can_edit` / `can_delete`).
class CategoriesScreen extends ConsumerWidget {
  const new({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider(groupId));
    final tree = categories.value ?? const <CategoryNode>[];
    final canReorder =
        ref.watch(groupPermissionsProvider(groupId))?.canReorderCategories ??
        false;
    return GroupThemed(
      groupId: groupId,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.categories),
          actions: [
            if (canReorder && tree.length > 1)
              IconButton(
                tooltip: context.l10n.reorder,
                icon: const Icon(Icons.swap_vert),
                onPressed: () => unawaited(
                  openCategoryOrder(
                    context,
                    groupId: groupId,
                    categories: [for (final node in tree) orderedNode(node)],
                    tree: tree,
                  ),
                ),
              ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'new-category',
          onPressed: () => unawaited(
            openCategoryForm(
              context,
              groupId: groupId,
              index: CategoryIndex(categories.value ?? const []),
            ),
          ),
          icon: const Icon(Icons.add),
          label: Text(context.l10n.newCategory),
        ),
        body: AsyncValueView(
          value: categories,
          onRetry: () => ref.invalidate(categoriesProvider(groupId)),
          data: (tree) {
            final index = CategoryIndex(tree);
            if (tree.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    context.l10n.noCategoriesHelp,
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () =>
                  settled([ref.refresh(categoriesProvider(groupId).future)]),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [
                  for (final node in tree)
                    _TopLevelTile(groupId: groupId, node: node, index: index),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TopLevelTile extends StatelessWidget {
  const new({required this.groupId, required this.node, required this.index});

  final String groupId;
  final CategoryNode node;
  final CategoryIndex index;

  @override
  Widget build(BuildContext context) {
    final fields = node.fieldDefs.length;
    final subs = node.subcategories.length;
    return ExpansionTile(
      key: PageStorageKey(node.id),
      leading: CategoryIcon(
        icon: node.icon,
        color: HexColor.tryParse(node.effectiveColor),
      ),
      title: Text(node.name),
      subtitle: Text(
        [
          context.l10n.subcategoryCount(subs),
          if (fields > 0) context.l10n.fieldCount(fields),
        ].join(' · '),
      ),
      trailing: _CategoryMenu(
        groupId: groupId,
        category: _asCategory(node),
        index: index,
        hasSubcategories: node.subcategories.isNotEmpty,
      ),
      childrenPadding: const EdgeInsetsDirectional.only(start: 24),
      children: [
        for (final sub in node.subcategories)
          ListTile(
            leading: CategoryIcon(
              icon: sub.icon ?? node.icon,
              color: HexColor.tryParse(sub.effectiveColor),
              size: 18,
            ),
            title: Text(sub.name),
            subtitle: sub.fieldDefs.isEmpty
                ? null
                : Text(context.l10n.ownFieldCount(sub.fieldDefs.length)),
            trailing: _CategoryMenu(
              groupId: groupId,
              category: sub,
              index: index,
              hasSubcategories: false,
            ),
          ),
        ListTile(
          leading: const Icon(Icons.add),
          title: Text(context.l10n.addSubcategoryTo(node.name)),
          onTap: () => unawaited(
            openCategoryForm(
              context,
              groupId: groupId,
              index: index,
              parentId: node.id,
            ),
          ),
        ),
      ],
    );
  }

  /// A top-level node as a plain [Category] (the form edits either).
  static Category _asCategory(CategoryNode node) => Category(
    id: node.id,
    groupId: node.groupId,
    parentId: node.parentId,
    name: node.name,
    color: node.color,
    effectiveColor: node.effectiveColor,
    icon: node.icon,
    position: node.position,
    fieldDefs: node.fieldDefs,
    effectiveFieldDefs: node.effectiveFieldDefs,
    createdBy: node.createdBy,
    canEdit: node.canEdit,
    canDelete: node.canDelete,
    createdAt: node.createdAt,
    updatedAt: node.updatedAt,
  );
}

class _CategoryMenu extends ConsumerWidget {
  const new({
    required this.groupId,
    required this.category,
    required this.index,
    required this.hasSubcategories,
  });

  final String groupId;
  final Category category;
  final CategoryIndex index;
  final bool hasSubcategories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!category.canEdit && !category.canDelete) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<String>(
      tooltip: context.l10n.optionsFor(category.name),
      onSelected: (action) => switch (action) {
        'edit' => unawaited(
          openCategoryForm(
            context,
            groupId: groupId,
            index: index,
            category: category,
            hasSubcategories: hasSubcategories,
          ),
        ),
        'delete' => unawaited(_delete(context, ref)),
        _ => null,
      },
      itemBuilder: (context) => [
        if (category.canEdit)
          PopupMenuItem(value: 'edit', child: Text(context.l10n.edit)),
        if (category.canDelete)
          PopupMenuItem(value: 'delete', child: Text(context.l10n.delete)),
      ],
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final parentName = index.name(category.parentId);
    final l10n = context.l10n;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.deleteNamedTitle(category.name),
      message: parentName != null
          ? l10n.categoryMovesTo(parentName)
          : hasSubcategories
          ? l10n.categoryDeleteWithSubs
          : l10n.categoryDeleteUncategorised,
      confirmLabel: l10n.delete,
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref
          .read(backlogControllerProvider.notifier)
          .deleteCategory(groupId, category.id);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.deletedNamed(category.name))),
      );
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    }
  }
}
