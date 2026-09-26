import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/date_only.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/forms/field_errors.dart';
import 'package:friends/core/forms/validators.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/core/widgets/form_widgets.dart';
import 'package:friends/core/widgets/version_conflict_dialog.dart';
import 'package:friends/features/backlog/data/backlog_controller.dart';
import 'package:friends/features/backlog/data/backlog_providers.dart';
import 'package:friends/features/backlog/domain/activity_rules.dart';
import 'package:friends/features/backlog/domain/category_index.dart';
import 'package:friends/features/backlog/domain/field_values.dart';
import 'package:friends/features/backlog/presentation/widgets/category_picker.dart';
import 'package:friends/features/backlog/presentation/widgets/category_visuals.dart';
import 'package:friends/features/backlog/presentation/widgets/dynamic_fields_form.dart';
import 'package:friends/features/groups/data/group_providers.dart';
import 'package:friends/features/groups/presentation/widgets/group_themed.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// Creates an activity (`/groups/:groupId/backlog/new`) or edits one
/// (`…/backlog/:activityId/edit`).
class ActivityFormScreen extends ConsumerWidget {
  /// The new-activity form.
  const new create({required this.groupId, super.key}) : activityId = null;

  /// The edit form of [activityId].
  const new edit({
    required this.groupId,
    required String this.activityId,
    super.key,
  });

  final String groupId;
  final String? activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoryIndexProvider(groupId));
    final members = ref.watch(membersProvider(groupId));
    final group = ref.watch(groupProvider(groupId));
    final activity = activityId == null
        ? const AsyncData<Activity?>(null)
        : ref
              .watch(activityProvider(activityId!))
              .whenData<Activity?>((a) => a);

    // All four must load; the first failure is shown.
    final all = switch ((categories, members, group, activity)) {
      (AsyncError(:final error, :final stackTrace), _, _, _) ||
      (_, AsyncError(:final error, :final stackTrace), _, _) ||
      (_, _, AsyncError(:final error, :final stackTrace), _) ||
      (
        _,
        _,
        _,
        AsyncError(:final error, :final stackTrace),
      ) => AsyncError<_FormData>(error, stackTrace),
      (
        AsyncData(value: final index),
        AsyncData(value: final members),
        AsyncData(value: final group),
        AsyncData(value: final activity),
      ) =>
        AsyncData(_FormData(index, members, group, activity)),
      _ => const AsyncLoading<_FormData>(),
    };

    return GroupThemed(
      groupId: groupId,
      child: Scaffold(
        appBar: AppBar(
          title: Text(activityId == null ? 'New idea' : 'Edit idea'),
        ),
        body: AsyncValueView(
          value: all,
          onRetry: () {
            ref
              ..invalidate(categoriesProvider(groupId))
              ..invalidate(membersProvider(groupId))
              ..invalidate(groupProvider(groupId));
            if (activityId != null) {
              ref.invalidate(activityProvider(activityId!));
            }
          },
          data: (data) => FormPage(
            maxWidth: 640,
            child: ActivityForm(
              // A reload after a version conflict starts over from the new
              // version.
              key: ValueKey(data.activity?.version),
              groupId: groupId,
              categories: data.categories,
              members: data.members,
              group: data.group,
              activity: data.activity,
            ),
          ),
        ),
      ),
    );
  }
}

class _FormData {
  const new(this.categories, this.members, this.group, this.activity);

  final CategoryIndex categories;
  final List<Member> members;
  final Group group;
  final Activity? activity;
}

/// The fields of an activity (contract section 9, `ActivityWrite`) and its
/// category's custom fields.
class ActivityForm extends ConsumerStatefulWidget {
  const new({
    required this.groupId,
    required this.categories,
    required this.members,
    required this.group,
    this.activity,
    super.key,
  });

  final String groupId;
  final CategoryIndex categories;
  final List<Member> members;
  final Group group;

  /// The activity being edited, or null to create one.
  final Activity? activity;

  /// Links per activity (contract section 1.9).
  static const maxLinks = 10;

  @override
  ConsumerState<ActivityForm> createState() => _ActivityFormState();
}

class _LinkDraft {
  new({String url = '', String label = ''})
    : url = TextEditingController(text: url),
      label = TextEditingController(text: label);

  final TextEditingController url;
  final TextEditingController label;

  void dispose() {
    url.dispose();
    label.dispose();
  }
}

class _ActivityFormState extends ConsumerState<ActivityForm>
    with ServerErrorsMixin {
  static const _fields = {
    'title',
    'description',
    'notes',
    'category_id',
    'owner_id',
    'status',
    'due_date',
    'estimated_cost',
    'currency',
    'location_name',
    'address',
    'links',
    'attributes',
  };

  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.activity?.title);
  late final _description = TextEditingController(
    text: widget.activity?.description,
  );
  late final _notes = TextEditingController(text: widget.activity?.notes);
  late final _cost = TextEditingController(
    text: widget.activity?.estimatedCost?.toString(),
  );
  late final _location = TextEditingController(
    text: widget.activity?.locationName,
  );
  late final _address = TextEditingController(text: widget.activity?.address);
  late final List<_LinkDraft> _links = [
    for (final link in widget.activity?.links ?? const <Link>[])
      _LinkDraft(url: link.url, label: link.label ?? ''),
  ];

  late String? _categoryId = widget.activity?.categoryId;
  late String? _ownerId = widget.activity?.owner?.id;
  late ActivityStatus _status = widget.activity?.status ?? ActivityStatus.idea;
  late DateTime? _dueDate = DateOnly.fromNullable(widget.activity?.dueDate);
  late bool _perPerson = widget.activity?.costPerPerson ?? true;

  /// Custom-field texts by key.
  late final Map<String, String> _attributes = {
    if (widget.activity?.attributes case final Map<Object?, Object?> stored)
      for (final MapEntry(:key, :value) in stored.entries)
        if (key is String && value != null) key: FieldValues.toText(value),
  };

  bool _saving = false;

  bool get _creating => widget.activity == null;

  @override
  void dispose() {
    for (final controller in [
      _title,
      _description,
      _notes,
      _cost,
      _location,
      _address,
    ]) {
      controller.dispose();
    }
    for (final link in _links) {
      link.dispose();
    }
    super.dispose();
  }

  static String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Map<String, Object?> _attributesJson(List<FieldDef> defs) => {
    for (final def in defs)
      def.key: ?FieldValues.parse(def, _attributes[def.key] ?? ''),
  };

  Future<void> _pickCategory() async {
    final choice = await showCategoryPicker(
      context,
      index: widget.categories,
      selectedId: _categoryId,
      noneLabel: 'No category',
    );
    if (choice is! PickedCategory || choice.id == _categoryId) return;
    final newKeys = {
      for (final def in widget.categories.fieldDefs(choice.id)) def.key,
    };
    final dropped = [
      for (final def in widget.categories.fieldDefs(_categoryId))
        if ((_attributes[def.key] ?? '').trim().isNotEmpty &&
            !newKeys.contains(def.key))
          def.label,
    ];
    if (dropped.isNotEmpty) {
      if (!mounted) return;
      final keep = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Change the category?'),
          content: Text(
            '${widget.categories.name(choice.id) ?? 'No category'} has no '
            '${dropped.length == 1 ? 'field' : 'fields'} for: '
            '${dropped.join(', ')}. '
            '${dropped.length == 1 ? 'It' : 'They'} will be removed when you '
            'save.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Change category'),
            ),
          ],
        ),
      );
      if (keep != true) return;
    }
    clearServerError('category_id');
    setState(() => _categoryId = choice.id);
  }

  Future<void> _pickDueDate() async {
    final today = DateOnly.today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate?.toLocalDate() ?? today.toLocalDate(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      clearServerError('due_date');
      setState(() => _dueDate = DateOnly.from(picked));
    }
  }

  Future<void> _save() async {
    clearFormError();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final controller = ref.read(backlogControllerProvider.notifier);
    final router = GoRouter.of(context);
    final defs = widget.categories.fieldDefs(_categoryId);
    final cost = int.tryParse(_cost.text.trim());
    final links = [
      for (final link in _links)
        if (link.url.text.trim().isNotEmpty)
          Link(url: link.url.text.trim(), label: _optional(link.label)),
    ];
    try {
      if (widget.activity case final activity?) {
        await controller.updateActivity(
          activity.id,
          ActivityUpdate(
            title: _title.text.trim(),
            version: activity.version,
            costPerPerson: _perPerson,
            description: _optional(_description),
            notes: _optional(_notes),
            categoryId: _categoryId,
            ownerId: _ownerId,
            dueDate: _dueDate,
            estimatedCost: cost,
            // Keep the stored currency (it may differ from the group's).
            currency: cost == null ? null : activity.currency,
            locationName: _optional(_location),
            address: _optional(_address),
            links: links,
            attributes: _attributesJson(defs),
          ),
        );
        if (router.canPop()) {
          router.pop();
        } else {
          router.go(Routes.activity(widget.groupId, activity.id));
        }
      } else {
        final created = await controller.createActivity(
          widget.groupId,
          ActivityCreate(
            title: _title.text.trim(),
            costPerPerson: _perPerson,
            status: _status,
            description: _optional(_description),
            notes: _optional(_notes),
            categoryId: _categoryId,
            ownerId: _ownerId,
            dueDate: _dueDate,
            estimatedCost: cost,
            locationName: _optional(_location),
            address: _optional(_address),
            links: links,
            attributes: _attributesJson(defs),
          ),
        );
        unawaited(
          router.replace<void>(Routes.activity(widget.groupId, created.id)),
        );
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error case ProblemException(code: ErrorCodes.versionConflict)) {
        setState(() => _saving = false);
        await showVersionConflictDialog(context);
        ref.invalidate(activityProvider(widget.activity!.id));
        return;
      }
      showServerError(
        error,
        fields: _fields,
        messages: const {
          ErrorCodes.forbidden:
              "You can't give this idea to that person. Only its owner or an "
              'admin can hand it over.',
        },
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<DropdownMenuItem<String?>> _ownerItems() {
    final me = ref.read(currentUserIdProvider);
    final role = widget.group.myRole;
    final rules = me == null
        ? null
        : OwnerRules(
            myRole: role,
            myUserId: me,
            ownerId: widget.activity?.owner?.id,
          );
    bool allowed(String? id) => _creating || (rules?.allows(id) ?? false);
    return [
      if (allowed(null))
        DropdownMenuItem(child: Text(_creating ? 'Me' : 'Nobody')),
      for (final member in widget.members)
        if (allowed(member.user.id) && !(_creating && member.user.id == me))
          DropdownMenuItem(
            value: member.user.id,
            child: Text(member.user.id == me ? 'Me' : member.user.displayName),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final defs = widget.categories.fieldDefs(_categoryId);
    final currency = widget.activity?.currency ?? widget.group.currency;
    final ownerItems = _ownerItems();
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (formError case final message?) ...[
            FormMessageBanner(message: message),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
            textCapitalization: TextCapitalization.sentences,
            maxLength: 120,
            validator: Validators.required('a title', max: 120),
            forceErrorText: serverError('title'),
            onChanged: (_) => clearServerError('title'),
          ),
          const SizedBox(height: 4),
          InputDecorator(
            decoration: InputDecoration(
              labelText: 'Category',
              errorText: serverError('category_id'),
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
            ),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: CategoryLabel(
                index: widget.categories,
                categoryId: _categoryId,
              ),
              trailing: const Icon(Icons.arrow_drop_down),
              onTap: () => unawaited(_pickCategory()),
            ),
          ),
          if (defs.isNotEmpty) ...[
            const SizedBox(height: 8),
            DynamicFieldsForm(
              fieldDefs: defs,
              values: _attributes,
              serverError: (key) => serverError('attributes.$key'),
              onChanged: (key, text) {
                clearServerError('attributes.$key');
                setState(() => _attributes[key] = text);
              },
            ),
          ],
          const SizedBox(height: 8),
          TextFormField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Description'),
            minLines: 2,
            maxLines: 6,
            maxLength: 5000,
            textCapitalization: TextCapitalization.sentences,
            forceErrorText: serverError('description'),
            onChanged: (_) => clearServerError('description'),
          ),
          if (ownerItems.length > 1 || _creating) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: ownerItems.any((item) => item.value == _ownerId)
                  ? _ownerId
                  : null,
              decoration: InputDecoration(
                labelText: "Who's on it",
                errorText: serverError('owner_id'),
              ),
              items: ownerItems,
              onChanged: (value) {
                clearServerError('owner_id');
                setState(() => _ownerId = value);
              },
            ),
          ],
          if (_creating) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<ActivityStatus>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: [
                for (final status in ActivityStatus.$valuesDefined)
                  DropdownMenuItem(value: status, child: Text(status.label)),
              ],
              onChanged: (value) => setState(() => _status = value ?? _status),
            ),
          ],
          const SizedBox(height: 16),
          InputDecorator(
            decoration: InputDecoration(
              labelText: 'Do it by',
              errorText: serverError('due_date'),
              suffixIcon: _dueDate == null
                  ? null
                  : IconButton(
                      tooltip: 'Clear the date',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _dueDate = null),
                    ),
            ),
            child: InkWell(
              onTap: () => unawaited(_pickDueDate()),
              child: Text(
                _dueDate == null
                    ? 'No date'
                    : DateFormat.yMMMd().format(_dueDate!.toLocalDate()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _cost,
                  decoration: InputDecoration(
                    labelText: 'Estimated cost',
                    suffixText: currency,
                    helperText: 'Whole amounts, roughly',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                  validator: (value) {
                    final amount = int.tryParse(value ?? '');
                    return amount != null && amount > 10000000
                        ? 'At most 10,000,000'
                        : null;
                  },
                  forceErrorText: serverError('estimated_cost'),
                  onChanged: (_) {
                    clearServerError('estimated_cost');
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Per person'),
                  value: _perPerson,
                  onChanged: _cost.text.trim().isEmpty
                      ? null
                      : (value) => setState(() => _perPerson = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _location,
            decoration: const InputDecoration(
              labelText: 'Place',
              hintText: "e.g. Ana's place",
            ),
            maxLength: 120,
            forceErrorText: serverError('location_name'),
            onChanged: (_) => clearServerError('location_name'),
          ),
          TextFormField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Address'),
            maxLength: 300,
            forceErrorText: serverError('address'),
            onChanged: (_) => clearServerError('address'),
          ),
          const SizedBox(height: 8),
          _linksEditor(context),
          const SizedBox(height: 8),
          TextFormField(
            controller: _notes,
            decoration: const InputDecoration(
              labelText: 'Notes',
              helperText: 'Anything else worth remembering',
            ),
            minLines: 2,
            maxLines: 6,
            maxLength: 5000,
            forceErrorText: serverError('notes'),
            onChanged: (_) => clearServerError('notes'),
          ),
          const SizedBox(height: 16),
          SubmitButton(
            label: _creating ? 'Add idea' : 'Save',
            busy: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  Widget _linksEditor(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Links', style: Theme.of(context).textTheme.titleSmall),
        for (final (index, link) in _links.indexed)
          Row(
            key: ObjectKey(link),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: link.url,
                  decoration: const InputDecoration(labelText: 'URL'),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  validator: (value) {
                    final url = (value ?? '').trim();
                    if (url.isEmpty) return null;
                    return FieldValues.isWebUrl(url)
                        ? null
                        : 'Enter a full http(s) link';
                  },
                  forceErrorText: serverError('links.$index.url'),
                  onChanged: (_) => clearServerError('links.$index'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: link.label,
                  decoration: const InputDecoration(labelText: 'Label'),
                  maxLength: 60,
                  forceErrorText: serverError('links.$index.label'),
                  onChanged: (_) => clearServerError('links.$index'),
                ),
              ),
              IconButton(
                tooltip: 'Remove link',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () {
                  clearServerError('links');
                  setState(() => _links.removeAt(index).dispose());
                },
              ),
            ],
          ),
        if (_links.length < ActivityForm.maxLinks)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() => _links.add(_LinkDraft())),
              icon: const Icon(Icons.add_link),
              label: const Text('Add a link'),
            ),
          ),
      ],
    );
  }
}

extension on DateTime {
  /// This date (a UTC midnight) as a local midnight, for date pickers and
  /// formatting.
  DateTime toLocalDate() => DateTime(year, month, day);
}
