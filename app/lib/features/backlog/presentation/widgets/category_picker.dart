import 'package:friends/core/theme/app_theme.dart';
import 'package:friends/features/backlog/domain/category_index.dart';
import 'package:friends/features/backlog/presentation/widgets/category_visuals.dart';
import 'package:material_ui/material_ui.dart';

/// What the category picker returned.
sealed class CategoryChoice {
  const new();
}

/// A category (or, with a null [id], "no category").
final class PickedCategory extends CategoryChoice {
  const new(this.id);

  final String? id;
}

/// A bottom sheet listing the category tree: each top-level category, then
/// its subcategories indented. Resolves to the choice, or null when
/// dismissed.
///
/// [noneLabel] adds a first row meaning "no category" (e.g. "All
/// categories" in a filter, "No category" in a form).
Future<CategoryChoice?> showCategoryPicker(
  BuildContext context, {
  required CategoryIndex index,
  required String? selectedId,
  required String noneLabel,
  String title = 'Category',
}) {
  return showModalBottomSheet<CategoryChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, controller) => CategoryPickerList(
        index: index,
        selectedId: selectedId,
        noneLabel: noneLabel,
        title: title,
        controller: controller,
        onPicked: (choice) => Navigator.of(context).pop(choice),
      ),
    ),
  );
}

/// The list inside [showCategoryPicker].
class CategoryPickerList extends StatelessWidget {
  const new({
    required this.index,
    required this.selectedId,
    required this.noneLabel,
    required this.onPicked,
    this.title = 'Category',
    this.controller,
    super.key,
  });

  final CategoryIndex index;
  final String? selectedId;
  final String noneLabel;
  final String title;
  final ScrollController? controller;
  final ValueChanged<CategoryChoice> onPicked;

  @override
  Widget build(BuildContext context) {
    Widget tile({
      required String? id,
      required String label,
      required Widget leading,
      double indent = 0,
    }) {
      final selected = id == selectedId;
      return ListTile(
        contentPadding: EdgeInsetsDirectional.only(start: 16 + indent, end: 16),
        leading: leading,
        title: Text(label),
        selected: selected,
        trailing: selected ? const Icon(Icons.check) : null,
        onTap: () => onPicked(PickedCategory(id)),
      );
    }

    return ListView(
      controller: controller,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        tile(id: null, label: noneLabel, leading: const Icon(Icons.clear_all)),
        for (final node in index.tree) ...[
          tile(
            id: node.id,
            label: node.name,
            leading: CategoryIcon(
              icon: node.icon,
              color: _color(node.effectiveColor),
            ),
          ),
          for (final sub in node.subcategories)
            tile(
              id: sub.id,
              label: sub.name,
              indent: 24,
              leading: CategoryIcon(
                icon: sub.icon ?? node.icon,
                color: _color(sub.effectiveColor),
                size: 18,
              ),
            ),
        ],
        if (index.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('This group has no categories yet.'),
          ),
      ],
    );
  }

  static Color? _color(String? hex) => HexColor.tryParse(hex);
}
