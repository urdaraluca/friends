import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/forms/field_errors.dart';
import 'package:friends/core/forms/validators.dart';
import 'package:friends/core/theme/app_theme.dart';
import 'package:friends/core/widgets/form_widgets.dart';
import 'package:friends/features/backlog/data/backlog_controller.dart';
import 'package:friends/features/backlog/domain/category_index.dart';
import 'package:friends/features/backlog/domain/field_values.dart';
import 'package:friends/features/backlog/presentation/widgets/category_visuals.dart';
import 'package:friends/features/groups/presentation/widgets/group_themed.dart';
import 'package:material_ui/material_ui.dart';

/// Colours offered for categories: the default categories' ones first
/// (contract section 6.5), then a few more.
const categoryColorPresets = <String, String>{
  '#7E57C2': 'Purple',
  '#EF6C00': 'Orange',
  '#2E7D32': 'Green',
  '#1565C0': 'Blue',
  '#00838F': 'Teal',
  '#AD1457': 'Pink',
  '#C62828': 'Red',
  '#F9A825': 'Yellow',
  '#6D4C41': 'Brown',
  '#546E7A': 'Grey',
};

/// Custom fields per category (contract section 6.1).
const maxOwnFields = 12;

/// Opens the category form: a new top-level category, a new subcategory of
/// [parentId], or [category] to edit. Resolves once it is closed.
Future<void> openCategoryForm(
  BuildContext context, {
  required String groupId,
  required CategoryIndex index,
  Category? category,
  String? parentId,
  bool hasSubcategories = false,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => GroupThemed(
        groupId: groupId,
        child: CategoryFormPage(
          groupId: groupId,
          index: index,
          category: category,
          parentId: category?.parentId ?? parentId,
          hasSubcategories: hasSubcategories,
        ),
      ),
    ),
  );
}

/// A category's name, parent, colour, icon and custom fields.
class CategoryFormPage extends ConsumerStatefulWidget {
  const new({
    required this.groupId,
    required this.index,
    this.category,
    this.parentId,
    this.hasSubcategories = false,
    super.key,
  });

  final String groupId;
  final CategoryIndex index;

  /// The category being edited, or null to create one.
  final Category? category;

  /// The parent to start with (a subcategory), or null for top level.
  final String? parentId;

  /// The edited category has subcategories, so it must stay top-level.
  final bool hasSubcategories;

  @override
  ConsumerState<CategoryFormPage> createState() => _CategoryFormPageState();
}

/// A field being edited. [locked] fields exist on the server: their key and
/// type can't change (contract section 6.2).
class _FieldDraft {
  new({
    required String label,
    required String key,
    required this.type,
    required this.locked,
    String options = '',
    String min = '',
    String max = '',
    this.showOnCard = false,
  }) : label = TextEditingController(text: label),
       keyText = TextEditingController(text: key),
       options = TextEditingController(text: options),
       min = TextEditingController(text: min),
       max = TextEditingController(text: max),
       keyEdited = locked;

  factory fromDef(FieldDef def) => _FieldDraft(
    label: def.label,
    key: def.key,
    type: def.type,
    locked: true,
    options: (def.options ?? const []).join('\n'),
    min: def.min == null ? '' : FieldValues.toText(def.min),
    max: def.max == null ? '' : FieldValues.toText(def.max),
    showOnCard: def.showOnCard,
  );

  final TextEditingController label;
  final TextEditingController keyText;
  final TextEditingController options;
  final TextEditingController min;
  final TextEditingController max;
  FieldType type;
  bool showOnCard;
  final bool locked;

  /// The key no longer follows the label.
  bool keyEdited;

  bool get hasRange => type == FieldType.number || type == FieldType.rating;

  FieldDef toDef() {
    num? number(TextEditingController c) =>
        num.tryParse(c.text.trim().replaceAll(',', '.'));
    return FieldDef(
      key: keyText.text.trim(),
      label: label.text.trim(),
      type: type,
      showOnCard: showOnCard,
      options: type == FieldType.select
          ? [
              for (final line in options.text.split('\n'))
                if (line.trim().isNotEmpty) line.trim(),
            ]
          : null,
      min: hasRange ? number(min) : null,
      max: hasRange ? number(max) : null,
    );
  }

  void dispose() {
    for (final c in [label, keyText, options, min, max]) {
      c.dispose();
    }
  }
}

class _CategoryFormPageState extends ConsumerState<CategoryFormPage>
    with ServerErrorsMixin {
  static const _fields = {
    'name',
    'parent_id',
    'color',
    'icon',
    'position',
    'field_defs',
  };

  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.category?.name);
  late final _emoji = TextEditingController(
    text: _isKnownIcon(widget.category?.icon) ? '' : widget.category?.icon,
  );
  late String? _parentId = widget.parentId;
  late String? _color =
      widget.category?.color ??
      (widget.parentId == null ? categoryColorPresets.keys.first : null);
  late String? _iconKey = _isKnownIcon(widget.category?.icon)
      ? widget.category!.icon
      : null;
  late final List<_FieldDraft> _drafts = [
    for (final def in widget.category?.fieldDefs ?? const <FieldDef>[])
      _FieldDraft.fromDef(def),
  ];
  bool _saving = false;

  bool get _creating => widget.category == null;
  bool get _isTopLevel => _parentId == null;

  static bool _isKnownIcon(String? icon) =>
      icon != null && categoryIcons.containsKey(icon);

  @override
  void dispose() {
    _name.dispose();
    _emoji.dispose();
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  String? get _icon {
    final emoji = _emoji.text.trim();
    return emoji.isNotEmpty ? emoji : _iconKey;
  }

  Future<void> _save() async {
    clearFormError();
    if (!_formKey.currentState!.validate()) return;
    if (_isTopLevel && _color == null) {
      setState(() {}); // shows the colour error
      return;
    }
    setState(() => _saving = true);
    final controller = ref.read(backlogControllerProvider.notifier);
    final navigator = Navigator.of(context);
    final body = CategoryWrite(
      name: _name.text.trim(),
      parentId: _parentId,
      color: _color,
      icon: _icon,
      fieldDefs: [for (final draft in _drafts) draft.toDef()],
    );
    try {
      if (widget.category case final category?) {
        await controller.updateCategory(widget.groupId, category.id, body);
      } else {
        await controller.createCategory(widget.groupId, body);
      }
      navigator.pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      showServerError(
        error,
        fields: _fields,
        codeFields: const {ErrorCodes.nameTaken: 'name'},
        messages: const {
          ErrorCodes.nameTaken: 'Another category here has this name.',
          ErrorCodes.categoryDepthExceeded:
              'Subcategories can only go under a top-level category.',
          ErrorCodes.fieldKeyConflict:
              'A field key is also used by the parent or a subcategory. '
              'Pick another key.',
          ErrorCodes.fieldTypeChange:
              "A field's type can't change. Remove the field and add it "
              'again instead.',
          ErrorCodes.limitReached: 'This group has 100 categories already.',
        },
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addField() {
    setState(
      () => _drafts.add(
        _FieldDraft(label: '', key: '', type: FieldType.text, locked: false),
      ),
    );
  }

  void _move(int index, int by) {
    final target = index + by;
    if (target < 0 || target >= _drafts.length) return;
    clearServerError('field_defs');
    setState(() {
      final draft = _drafts.removeAt(index);
      _drafts.insert(target, draft);
    });
  }

  @override
  Widget build(BuildContext context) {
    final parents = [
      for (final node in widget.index.tree)
        if (node.id != widget.category?.id) node,
    ];
    final parentFieldCount = _parentId == null
        ? 0
        : widget.index.fieldDefs(_parentId).length;
    final parentNote = parentFieldCount == 0
        ? ''
        : ' It also gets the $parentFieldCount fields of '
              '${widget.index.name(_parentId)}.';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _creating
              ? (widget.parentId == null ? 'New category' : 'New subcategory')
              : 'Edit ${widget.category!.name}',
        ),
      ),
      body: FormPage(
        maxWidth: 640,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (formError case final message?) ...[
                FormMessageBanner(message: message),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                textCapitalization: TextCapitalization.sentences,
                maxLength: 40,
                validator: Validators.required('a name', max: 40),
                forceErrorText: serverError('name'),
                onChanged: (_) => clearServerError('name'),
              ),
              DropdownButtonFormField<String?>(
                initialValue: _parentId,
                decoration: InputDecoration(
                  labelText: 'Inside',
                  helperText: widget.hasSubcategories
                      ? 'It has subcategories, so it stays top-level'
                      : null,
                  errorText: serverError('parent_id'),
                ),
                items: [
                  const DropdownMenuItem(child: Text('Nothing (top level)')),
                  for (final parent in parents)
                    DropdownMenuItem(
                      value: parent.id,
                      child: Text(parent.name),
                    ),
                ],
                onChanged: widget.hasSubcategories
                    ? null
                    : (value) {
                        clearServerError('parent_id');
                        setState(() {
                          _parentId = value;
                          if (value == null) {
                            _color ??= categoryColorPresets.keys.first;
                          }
                        });
                      },
              ),
              const SizedBox(height: 16),
              Text('Colour', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!_isTopLevel)
                    ChoiceChip(
                      label: const Text("Parent's"),
                      selected: _color == null,
                      onSelected: (_) => setState(() => _color = null),
                    ),
                  for (final MapEntry(key: hex, value: name)
                      in categoryColorPresets.entries)
                    _Swatch(
                      hex: hex,
                      name: name,
                      selected: _color?.toUpperCase() == hex,
                      onTap: () {
                        clearServerError('color');
                        setState(() => _color = hex);
                      },
                    ),
                ],
              ),
              if (serverError('color') ??
                      (_isTopLevel && _color == null ? 'Pick a colour' : null)
                  case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text('Icon', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final MapEntry(:key, value: icon)
                      in categoryIcons.entries)
                    IconButton.outlined(
                      tooltip: key,
                      isSelected: _iconKey == key && _emoji.text.isEmpty,
                      onPressed: () {
                        _emoji.clear();
                        setState(() => _iconKey = key);
                      },
                      icon: Icon(icon),
                    ),
                ],
              ),
              TextFormField(
                controller: _emoji,
                decoration: const InputDecoration(
                  labelText: 'Or an emoji',
                  hintText: 'e.g. 🎳',
                ),
                inputFormatters: [LengthLimitingTextInputFormatter(40)],
                forceErrorText: serverError('icon'),
                onChanged: (_) {
                  clearServerError('icon');
                  setState(() {});
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Custom fields',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Extra details every idea in this category can have, like an '
                'IMDb rating for movies.$parentNote',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final (index, draft) in _drafts.indexed)
                _FieldEditor(
                  key: ObjectKey(draft),
                  draft: draft,
                  index: index,
                  count: _drafts.length,
                  serverError: serverError,
                  onChanged: () {
                    clearServerError('field_defs.$index');
                    setState(() {});
                  },
                  onMove: (by) => _move(index, by),
                  onRemove: () {
                    clearServerError('field_defs');
                    setState(() => _drafts.removeAt(index).dispose());
                  },
                ),
              if (_drafts.length < maxOwnFields)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _addField,
                    icon: const Icon(Icons.add),
                    label: const Text('Add a field'),
                  ),
                ),
              const SizedBox(height: 16),
              SubmitButton(
                label: _creating ? 'Create' : 'Save',
                busy: _saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const new({
    required this.hex,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: Tooltip(
        message: name,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: HexColor.tryParse(hex),
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.onSurface,
                      width: 3,
                    )
                  : null,
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : null,
          ),
        ),
      ),
    );
  }
}

class _FieldEditor extends StatelessWidget {
  const new({
    required this.draft,
    required this.index,
    required this.count,
    required this.serverError,
    required this.onChanged,
    required this.onMove,
    required this.onRemove,
    super.key,
  });

  final _FieldDraft draft;
  final int index;
  final int count;
  final String? Function(String field) serverError;
  final VoidCallback onChanged;
  final ValueChanged<int> onMove;
  final VoidCallback onRemove;

  String? _error(String part) => serverError('field_defs.$index.$part');

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Field ${index + 1}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Move up',
                  onPressed: index == 0 ? null : () => onMove(-1),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Move down',
                  onPressed: index == count - 1 ? null : () => onMove(1),
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: 'Remove field',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: draft.label,
                    decoration: const InputDecoration(labelText: 'Label'),
                    maxLength: 40,
                    validator: Validators.required('a label', max: 40),
                    forceErrorText: _error('label'),
                    onChanged: (label) {
                      if (!draft.keyEdited) {
                        draft.keyText.text = FieldValues.keyFromLabel(label);
                      }
                      onChanged();
                    },
                  ),
                  TextFormField(
                    controller: draft.keyText,
                    readOnly: draft.locked,
                    decoration: InputDecoration(
                      labelText: 'Key',
                      helperText: draft.locked
                          ? 'Stored values use this key, so it stays'
                          : 'Lowercase letters, digits and _',
                    ),
                    validator: (value) =>
                        FieldValues.isValidKey((value ?? '').trim())
                        ? null
                        : 'Start with a letter; a-z, 0-9 and _ only',
                    forceErrorText: _error('key'),
                    onChanged: (_) {
                      draft.keyEdited = true;
                      onChanged();
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<FieldType>(
                    initialValue: draft.type,
                    decoration: InputDecoration(
                      labelText: 'Type',
                      helperText: draft.locked
                          ? 'To change the type, remove the field and add it '
                                'again'
                          : null,
                      helperMaxLines: 2,
                      errorText: _error('type'),
                    ),
                    items: [
                      for (final type in FieldType.$valuesDefined)
                        DropdownMenuItem(value: type, child: Text(type.label)),
                    ],
                    onChanged: draft.locked
                        ? null
                        : (type) {
                            if (type == null) return;
                            draft.type = type;
                            onChanged();
                          },
                  ),
                  if (draft.type == FieldType.select)
                    TextFormField(
                      controller: draft.options,
                      decoration: InputDecoration(
                        labelText: 'Options, one per line',
                        errorText: _error('options'),
                      ),
                      minLines: 2,
                      maxLines: 8,
                      validator: (value) {
                        final options = [
                          for (final line in (value ?? '').split('\n'))
                            if (line.trim().isNotEmpty) line.trim(),
                        ];
                        if (options.isEmpty) return 'Add at least one option';
                        if (options.length > 30) return 'At most 30 options';
                        final lower = options.map((o) => o.toLowerCase());
                        if (lower.toSet().length != options.length) {
                          return 'Each option only once';
                        }
                        return null;
                      },
                      onChanged: (_) => onChanged(),
                    ),
                  if (draft.hasRange)
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: draft.min,
                            decoration: InputDecoration(
                              labelText: 'Min',
                              hintText: draft.type == FieldType.rating
                                  ? '0'
                                  : null,
                              errorText: _error('min'),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            onChanged: (_) => onChanged(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: draft.max,
                            decoration: InputDecoration(
                              labelText: 'Max',
                              hintText: draft.type == FieldType.rating
                                  ? '10'
                                  : null,
                              errorText: _error('max'),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            onChanged: (_) => onChanged(),
                          ),
                        ),
                      ],
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show on the card'),
                    subtitle: const Text('e.g. the rating of a movie'),
                    value: draft.showOnCard,
                    onChanged: (value) {
                      draft.showOnCard = value;
                      onChanged();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
