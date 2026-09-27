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
import 'package:friends/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Colours offered for categories: the default categories' ones first
/// (contract section 6.5), then a few more.
Map<String, String> get categoryColorPresets {
  final l10n = currentL10n;
  return {
    '#7E57C2': l10n.colourPurple,
    '#EF6C00': l10n.colourOrange,
    '#2E7D32': l10n.colourGreen,
    '#1565C0': l10n.colourBlue,
    '#00838F': l10n.colourTeal,
    '#AD1457': l10n.colourPink,
    '#C62828': l10n.colourRed,
    '#F9A825': l10n.colourYellow,
    '#6D4C41': l10n.colourBrown,
    '#546E7A': l10n.colourGrey,
  };
}

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
        messages: {
          ErrorCodes.nameTaken: currentL10n.categoryNameTaken,
          ErrorCodes.categoryDepthExceeded: currentL10n.categoryDepthExceeded,
          ErrorCodes.fieldKeyConflict: currentL10n.fieldKeyConflict,
          ErrorCodes.fieldTypeChange: currentL10n.fieldTypeChange,
          ErrorCodes.limitReached: currentL10n.categoryLimitReached,
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
    final parentName = widget.index.name(_parentId) ?? '';
    final parentNote = parentFieldCount == 0
        ? ''
        : ' ${context.l10n.parentFieldsNote(parentFieldCount, parentName)}';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _creating
              ? (widget.parentId == null
                    ? context.l10n.newCategory
                    : context.l10n.newSubcategory)
              : context.l10n.editNamed(widget.category!.name),
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
                decoration: InputDecoration(labelText: context.l10n.nameLabel),
                textCapitalization: TextCapitalization.sentences,
                maxLength: 40,
                validator: Validators.required(context.l10n.enterName, max: 40),
                forceErrorText: serverError('name'),
                onChanged: (_) => clearServerError('name'),
              ),
              DropdownButtonFormField<String?>(
                initialValue: _parentId,
                decoration: InputDecoration(
                  labelText: context.l10n.insideLabel,
                  helperText: widget.hasSubcategories
                      ? context.l10n.staysTopLevel
                      : null,
                  errorText: serverError('parent_id'),
                ),
                items: [
                  DropdownMenuItem(child: Text(context.l10n.nothingTopLevel)),
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
              Text(
                context.l10n.colourLabel,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!_isTopLevel)
                    ChoiceChip(
                      label: Text(context.l10n.parentsColour),
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
                      (_isTopLevel && _color == null
                          ? context.l10n.pickColour
                          : null)
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
              Text(
                context.l10n.iconLabel,
                style: Theme.of(context).textTheme.titleSmall,
              ),
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
                decoration: InputDecoration(
                  labelText: context.l10n.orEmoji,
                  hintText: context.l10n.emojiHintBowling,
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
                context.l10n.customFields,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${context.l10n.customFieldsHelp}$parentNote',
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
                    label: Text(context.l10n.addField),
                  ),
                ),
              const SizedBox(height: 16),
              SubmitButton(
                label: _creating ? context.l10n.create : context.l10n.save,
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
                    context.l10n.fieldNumber(index + 1),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.moveUp,
                  onPressed: index == 0 ? null : () => onMove(-1),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: context.l10n.moveDown,
                  onPressed: index == count - 1 ? null : () => onMove(1),
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: context.l10n.removeField,
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
                    decoration: InputDecoration(
                      labelText: context.l10n.labelField,
                    ),
                    maxLength: 40,
                    validator: Validators.required(
                      context.l10n.enterLabel,
                      max: 40,
                    ),
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
                      labelText: context.l10n.keyLabel,
                      helperText: draft.locked
                          ? context.l10n.keyLocked
                          : context.l10n.keyHelper,
                    ),
                    validator: (value) =>
                        FieldValues.isValidKey((value ?? '').trim())
                        ? null
                        : context.l10n.keyInvalid,
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
                      labelText: context.l10n.typeLabel,
                      helperText: draft.locked ? context.l10n.typeLocked : null,
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
                        labelText: context.l10n.optionsPerLine,
                        errorText: _error('options'),
                      ),
                      minLines: 2,
                      maxLines: 8,
                      validator: (value) {
                        final options = [
                          for (final line in (value ?? '').split('\n'))
                            if (line.trim().isNotEmpty) line.trim(),
                        ];
                        if (options.isEmpty) return context.l10n.addOneOption;
                        if (options.length > 30) {
                          return context.l10n.atMostOptions;
                        }
                        final lower = options.map((o) => o.toLowerCase());
                        if (lower.toSet().length != options.length) {
                          return context.l10n.optionOnce;
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
                              labelText: context.l10n.minLabel,
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
                              labelText: context.l10n.maxLabel,
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
                    title: Text(context.l10n.showOnCard),
                    subtitle: Text(context.l10n.showOnCardHelp),
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
