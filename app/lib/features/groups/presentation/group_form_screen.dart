import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/device/device_info.dart';
import 'package:friends/core/forms/field_errors.dart';
import 'package:friends/core/forms/validators.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/theme/app_theme.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/core/widgets/form_widgets.dart';
import 'package:friends/features/groups/data/group_providers.dart';
import 'package:friends/features/groups/data/groups_controller.dart';
import 'package:friends/features/groups/domain/group_colors.dart';
import 'package:friends/features/groups/domain/group_kinds.dart';
import 'package:friends/features/groups/domain/group_permissions.dart';
import 'package:friends/features/groups/presentation/widgets/group_not_found_view.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Creates a group (`/groups/new`) or edits one (`/groups/:groupId/edit`,
/// admin+).
class GroupFormScreen extends ConsumerWidget {
  /// The create form.
  const new create({super.key}) : groupId = null;

  /// The edit form of [groupId].
  const new edit({required String this.groupId, super.key});

  /// The group to edit, or null to create one.
  final String? groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupId = this.groupId;
    return Scaffold(
      appBar: AppBar(
        // Opened directly (a deep link or a reload): nothing to pop.
        leading: context.canPop()
            ? null
            : IconButton(
                tooltip: context.l10n.close,
                icon: const Icon(Icons.close),
                onPressed: () => context.go(
                  groupId == null ? Routes.groups : Routes.groupHub(groupId),
                ),
              ),
        title: Text(
          groupId == null ? context.l10n.newGroup : context.l10n.editGroup,
        ),
      ),
      body: groupId == null
          ? const FormPage(maxWidth: 560, child: GroupForm())
          : _EditBody(groupId: groupId),
    );
  }
}

class _EditBody extends ConsumerWidget {
  const new({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupProvider(groupId));
    if (group case AsyncError(:final error) when isGroupNotFound(error)) {
      return const GroupNotFoundView();
    }
    return AsyncValueView(
      value: group,
      onRetry: () => ref.invalidate(groupProvider(groupId)),
      data: (group) => group.myRole.isAdminOrOwner
          ? FormPage(
              maxWidth: 560,
              child: GroupForm(key: ValueKey(group.id), group: group),
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(context.l10n.onlyAdminsEditGroup),
              ),
            ),
    );
  }
}

/// The group fields: name (1..60), description (≤500), emoji (≤16), a
/// colour from [groupColorPresets], currency (3 capital letters, default
/// EUR) and timezone (default: the device's). Creating adds the "default
/// categories" switch; editing adds "members can invite" (contract section
/// 9, `GroupCreate` and `GroupUpdate`).
class GroupForm extends ConsumerStatefulWidget {
  const new({this.group, super.key});

  /// The group to edit, or null to create one.
  final Group? group;

  @override
  ConsumerState<GroupForm> createState() => _GroupFormState();
}

class _GroupFormState extends ConsumerState<GroupForm> with ServerErrorsMixin {
  static const _fields = {
    'name',
    'description',
    'emoji',
    'color',
    'currency',
    'timezone',
  };

  static Map<String, String> get _messages => {
    ErrorCodes.limitReached: currentL10n.groupLimitReached,
  };

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _emoji;
  late final TextEditingController _currency;
  late final TextEditingController _timezone;
  String? _color;
  late GroupKind _kind;
  bool _seedDefaultCategories = true;
  late bool _membersCanInvite;
  bool _saving = false;

  bool get _creating => widget.group == null;

  @override
  void initState() {
    super.initState();
    final group = widget.group;
    _name = TextEditingController(text: group?.name);
    _description = TextEditingController(text: group?.description);
    _emoji = TextEditingController(text: group?.emoji);
    _currency = TextEditingController(
      text: group?.currency ?? currentL10n.defaultCurrency,
    );
    _timezone = TextEditingController(text: group?.timezone);
    _color = group == null ? groupColorPresets.keys.first : group.color;
    _membersCanInvite = group?.membersCanInvite ?? true;
    _kind = switch (group?.kind) {
      null || GroupKind.$unknown => GroupKind.general,
      final kind => kind,
    };
    if (group == null) unawaited(_useDeviceTimezone());
  }

  /// A new group's timezone defaults to the device's.
  Future<void> _useDeviceTimezone() async {
    final zone = await ref.read(deviceTimezoneProvider.future);
    if (mounted && _timezone.text.trim().isEmpty) {
      setState(() => _timezone.text = zone);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _emoji.dispose();
    _currency.dispose();
    _timezone.dispose();
    super.dispose();
  }

  static String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _save() async {
    clearFormError();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final controller = ref.read(groupsControllerProvider.notifier);
    final router = GoRouter.of(context);
    try {
      final group = widget.group;
      if (group == null) {
        final created = await controller.create(
          GroupCreate(
            name: _name.text.trim(),
            description: _optional(_description),
            emoji: _optional(_emoji),
            color: _color,
            currency: Validators.normalizeCurrency(_currency.text),
            timezone: _timezone.text.trim(),
            kind: _kind,
            seedDefaultCategories: _seedDefaultCategories,
          ),
        );
        router.go(Routes.groupBacklog(created.id));
      } else {
        await controller.updateGroup(
          group.id,
          GroupUpdate(
            name: _name.text.trim(),
            description: _optional(_description),
            emoji: _optional(_emoji),
            color: _color,
            currency: Validators.normalizeCurrency(_currency.text),
            timezone: _timezone.text.trim(),
            kind: _kind,
            membersCanInvite: _membersCanInvite,
          ),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.l10n.groupSaved)));
        if (router.canPop()) {
          router.pop();
        } else {
          router.go(Routes.groupHub(group.id));
        }
      }
    } on ApiException catch (e) {
      if (mounted) showServerError(e, fields: _fields, messages: _messages);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceZone = ref.watch(deviceTimezoneProvider).value;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (formError case final message?) ...[
            FormMessageBanner(message: message),
            const SizedBox(height: 16),
          ],
          Text(
            context.l10n.groupKindLabel,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          GroupKindPicker(
            selected: _kind,
            onSelected: (kind) => setState(() => _kind = kind),
          ),
          const SizedBox(height: 4),
          Text(
            [
              _kind.help,
              if (!_creating) context.l10n.groupKindChangeNote,
            ].join(' '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            decoration: InputDecoration(labelText: context.l10n.nameLabel),
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            validator: Validators.required(context.l10n.enterName, max: 60),
            forceErrorText: serverError('name'),
            onChanged: (_) => clearServerError('name'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _emoji,
            decoration: InputDecoration(
              labelText: context.l10n.emojiLabel,
              hintText: context.l10n.emojiHint,
              helperText: context.l10n.optional,
            ),
            textInputAction: TextInputAction.next,
            validator: Validators.optional(max: 16),
            forceErrorText: serverError('emoji'),
            onChanged: (_) => clearServerError('emoji'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            decoration: InputDecoration(
              labelText: context.l10n.descriptionLabel,
              helperText: context.l10n.optional,
            ),
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            validator: Validators.optional(max: 500),
            forceErrorText: serverError('description'),
            onChanged: (_) => clearServerError('description'),
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.colourLabel,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _ColorSwatches(
            selected: _color,
            onSelected: (color) {
              clearServerError('color');
              setState(() => _color = color);
            },
          ),
          if (serverError('color') case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _currency,
            decoration: InputDecoration(
              labelText: context.l10n.currencyLabel,
              helperText: context.l10n.currencyHelper,
            ),
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.next,
            validator: Validators.currency,
            forceErrorText: serverError('currency'),
            onChanged: (_) => clearServerError('currency'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _timezone,
            decoration: InputDecoration(
              labelText: context.l10n.timezoneLabel,
              helperText: context.l10n.timezoneHelper,
            ),
            autocorrect: false,
            validator: Validators.required(context.l10n.enterTimezone, max: 64),
            forceErrorText: serverError('timezone'),
            onChanged: (_) {
              clearServerError('timezone');
              setState(() {});
            },
          ),
          if (deviceZone != null && deviceZone != _timezone.text.trim())
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () {
                  clearServerError('timezone');
                  setState(() => _timezone.text = deviceZone);
                },
                icon: const Icon(Icons.my_location),
                label: Text(context.l10n.useDeviceTimezone(deviceZone)),
              ),
            ),
          const SizedBox(height: 8),
          if (_creating)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.addDefaultCategories),
              subtitle: Text(switch (_kind) {
                GroupKind.movieNight => context.l10n.addMovieCategoryHelp,
                GroupKind.bookClub => context.l10n.addBookCategoryHelp,
                _ => context.l10n.addDefaultCategoriesHelp,
              }),
              value: _seedDefaultCategories,
              onChanged: (value) =>
                  setState(() => _seedDefaultCategories = value),
            )
          else
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.membersCanInvite),
              subtitle: Text(context.l10n.membersCanInviteHelp),
              value: _membersCanInvite,
              onChanged: (value) => setState(() => _membersCanInvite = value),
            ),
          const SizedBox(height: 16),
          SubmitButton(
            label: _creating ? context.l10n.createGroup : context.l10n.save,
            busy: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

/// The preset colours; a colour set elsewhere that isn't a preset is kept
/// as an extra swatch.
class _ColorSwatches extends StatelessWidget {
  const new({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = this.selected?.toUpperCase();
    final swatches = {
      if (selected != null && !groupColorPresets.containsKey(selected))
        selected: context.l10n.currentColour,
      ...groupColorPresets,
    };
    final outline = Theme.of(context).colorScheme.onSurface;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final MapEntry(key: hex, value: name) in swatches.entries)
          Semantics(
            button: true,
            selected: hex == selected,
            label: name,
            child: Tooltip(
              message: name,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onSelected(hex),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: HexColor.tryParse(hex),
                    shape: BoxShape.circle,
                    border: hex == selected
                        ? Border.all(color: outline, width: 3)
                        : null,
                  ),
                  child: hex == selected
                      ? const Icon(Icons.check, color: Colors.white)
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// What a group is for: anything, a movie night or a book club (contract
/// section 17.1).
class GroupKindPicker extends StatelessWidget {
  const new({required this.selected, required this.onSelected, super.key});

  final GroupKind selected;
  final ValueChanged<GroupKind> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final kind in GroupKind.$valuesDefined)
          ChoiceChip(
            avatar: Icon(kind.icon, size: 18),
            label: Text(kind.label),
            selected: kind == selected,
            showCheckmark: false,
            onSelected: (_) => onSelected(kind),
          ),
      ],
    );
  }
}
