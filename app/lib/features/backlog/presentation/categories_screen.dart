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
import 'package:friends/features/backlog/presentation/widgets/category_visuals.dart';
import 'package:friends/features/groups/presentation/widgets/group_themed.dart';
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
    return GroupThemed(
      groupId: groupId,
      child: Scaffold(
        appBar: AppBar(title: const Text('Categories')),
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
          label: const Text('New category'),
        ),
        body: AsyncValueView(
          value: categories,
          onRetry: () => ref.invalidate(categoriesProvider(groupId)),
          data: (tree) {
            final index = CategoryIndex(tree);
            if (tree.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No categories yet. Categories group your ideas '
                    '(movies, trips, food…) and can add their own fields, '
                    'like an IMDb rating for movies.',
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
          '$subs ${subs == 1 ? 'subcategory' : 'subcategories'}',
          if (fields > 0) '$fields ${fields == 1 ? 'field' : 'fields'}',
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
                : Text('${sub.fieldDefs.length} own fields'),
            trailing: _CategoryMenu(
              groupId: groupId,
              category: sub,
              index: index,
              hasSubcategories: false,
            ),
          ),
        ListTile(
          leading: const Icon(Icons.add),
          title: Text('Add a subcategory to ${node.name}'),
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
      tooltip: 'Options for ${category.name}',
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
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (category.canDelete)
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final parentName = index.name(category.parentId);
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete "${category.name}"?',
      message: parentName != null
          ? 'Its ideas and plans move to "$parentName".'
          : hasSubcategories
          ? 'Its subcategories are deleted too, and all their ideas and plans '
                'become uncategorised.'
          : 'Its ideas and plans become uncategorised.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref
          .read(backlogControllerProvider.notifier)
          .deleteCategory(groupId, category.id);
      messenger.showSnackBar(
        SnackBar(content: Text('Deleted "${category.name}"')),
      );
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    }
  }
}
