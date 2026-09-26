import 'package:friends/core/api/generated/export.dart';

/// A group's categories (`GET /groups/{id}/categories`) indexed by ID, for
/// activity cards, pickers and forms.
///
/// Top-level categories come in the server's order (position, then name),
/// each followed by its subcategories.
class CategoryIndex {
  new(this.tree)
    : _byId = {
        for (final node in tree) ...{
          node.id: _TopLevel(node),
          for (final sub in node.subcategories) sub.id: _Sub(sub, node),
        },
      };

  /// An index with no categories.
  factory empty() => CategoryIndex(const []);

  /// The top-level categories, each with its subcategories.
  final List<CategoryNode> tree;
  final Map<String, _Entry> _byId;

  /// Whether the group has any category.
  bool get isEmpty => tree.isEmpty;

  /// Whether [id] is a known category.
  bool contains(String? id) => id != null && _byId.containsKey(id);

  /// The category's name, or null when unknown.
  String? name(String? id) => _byId[id]?.name;

  /// "Parent › Sub" for a subcategory, the name otherwise.
  String? path(String? id) => switch (_byId[id]) {
    _Sub(:final sub, :final parent) => '${parent.name} › ${sub.name}',
    final _TopLevel entry => entry.name,
    null => null,
  };

  /// The category's own colour, or its parent's for a subcategory without
  /// one (`effective_color`).
  String? color(String? id) => _byId[id]?.effectiveColor;

  /// The category's icon, or its parent's for a subcategory without one.
  String? icon(String? id) => switch (_byId[id]) {
    _Sub(:final sub, :final parent) => sub.icon ?? parent.icon,
    final _TopLevel entry => entry.node.icon,
    null => null,
  };

  /// The parent's field definitions followed by the category's own
  /// (`effective_field_defs`); none for an unknown or null category.
  List<FieldDef> fieldDefs(String? id) => _byId[id]?.effectiveFieldDefs ?? [];

  /// The ID of the category's parent, or null for a top-level one.
  String? parentId(String? id) => switch (_byId[id]) {
    _Sub(:final parent) => parent.id,
    _ => null,
  };

  /// Whether the category can be edited or deleted by me (`can_edit`).
  bool canEdit(String? id) => _byId[id]?.canEdit ?? false;
}

sealed class _Entry {
  String get name;
  String? get effectiveColor;
  List<FieldDef> get effectiveFieldDefs;
  bool get canEdit;
}

final class _TopLevel extends _Entry {
  new(this.node);

  final CategoryNode node;

  @override
  String get name => node.name;

  @override
  String? get effectiveColor => node.effectiveColor;

  @override
  List<FieldDef> get effectiveFieldDefs => node.effectiveFieldDefs;

  @override
  bool get canEdit => node.canEdit;
}

final class _Sub extends _Entry {
  new(this.sub, this.parent);

  final Category sub;
  final CategoryNode parent;

  @override
  String get name => sub.name;

  @override
  String? get effectiveColor => sub.effectiveColor;

  @override
  List<FieldDef> get effectiveFieldDefs => sub.effectiveFieldDefs;

  @override
  bool get canEdit => sub.canEdit;
}
