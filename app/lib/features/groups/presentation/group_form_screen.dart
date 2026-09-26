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
import 'package:friends/features/groups/domain/group_permissions.dart';
import 'package:friends/features/groups/presentation/widgets/group_not_found_view.dart';
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
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => context.go(
                  groupId == null ? Routes.groups : Routes.groupHub(groupId),
                ),
              ),
        title: Text(groupId == null ? 'New group' : 'Edit group'),
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
          : const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Only admins can edit this group.'),
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

  static const Map<String, String> _messages = {
    ErrorCodes.limitReached: "You're in 50 groups already, the most allowed.",
  };

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _emoji;
  late final TextEditingController _currency;
  late final TextEditingController _timezone;
  String? _color;
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
    _currency = TextEditingController(text: group?.currency ?? 'EUR');
    _timezone = TextEditingController(text: group?.timezone);
    _color = group == null ? groupColorPresets.keys.first : group.color;
    _membersCanInvite = group?.membersCanInvite ?? true;
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
            membersCanInvite: _membersCanInvite,
          ),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Group saved')));
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
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            validator: Validators.required('a name', max: 60),
            forceErrorText: serverError('name'),
            onChanged: (_) => clearServerError('name'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _emoji,
            decoration: const InputDecoration(
              labelText: 'Emoji',
              hintText: 'e.g. 🎬',
              helperText: 'Optional',
            ),
            textInputAction: TextInputAction.next,
            validator: Validators.optional(max: 16),
            forceErrorText: serverError('emoji'),
            onChanged: (_) => clearServerError('emoji'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            decoration: const InputDecoration(
              labelText: 'Description',
              helperText: 'Optional',
            ),
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            validator: Validators.optional(max: 500),
            forceErrorText: serverError('description'),
            onChanged: (_) => clearServerError('description'),
          ),
          const SizedBox(height: 16),
          Text('Colour', style: Theme.of(context).textTheme.titleSmall),
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
            decoration: const InputDecoration(
              labelText: 'Currency',
              helperText: 'For activity costs, e.g. EUR',
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
            decoration: const InputDecoration(
              labelText: 'Timezone',
              helperText: 'IANA name, e.g. Europe/Bucharest',
            ),
            autocorrect: false,
            validator: Validators.required('a timezone', max: 64),
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
                label: Text('Use device timezone ($deviceZone)'),
              ),
            ),
          const SizedBox(height: 8),
          if (_creating)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Add default categories'),
              subtitle: const Text('Movies, trips, food and more to start'),
              value: _seedDefaultCategories,
              onChanged: (value) =>
                  setState(() => _seedDefaultCategories = value),
            )
          else
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Members can invite'),
              subtitle: const Text(
                'When off, only admins can create invite links',
              ),
              value: _membersCanInvite,
              onChanged: (value) => setState(() => _membersCanInvite = value),
            ),
          const SizedBox(height: 16),
          SubmitButton(
            label: _creating ? 'Create group' : 'Save',
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
        selected: 'Current colour',
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
