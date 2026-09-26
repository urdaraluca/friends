import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/forms/field_errors.dart';
import 'package:friends/core/invites/invite_code.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/core/widgets/confirm_dialog.dart';
import 'package:friends/core/widgets/form_widgets.dart';
import 'package:friends/features/groups/data/group_providers.dart';
import 'package:friends/features/groups/data/groups_controller.dart';
import 'package:friends/features/groups/domain/group_permissions.dart';
import 'package:friends/features/groups/presentation/widgets/group_action.dart';
import 'package:friends/features/invites/data/invite_sharer.dart';
import 'package:friends/features/invites/presentation/invite_labels.dart';
import 'package:material_ui/material_ui.dart';

/// Copies [code] as `XXXXX-XXXXX`.
Future<void> copyInviteCode(BuildContext context, String code) async {
  final messenger = ScaffoldMessenger.of(context);
  await Clipboard.setData(ClipboardData(text: InviteCode.format(code)));
  messenger.showSnackBar(const SnackBar(content: Text('Code copied')));
}

/// Shares [invite]'s link through the platform share sheet, pointing from
/// the widget of [context] (iPad, macOS).
Future<void> shareInvite(
  BuildContext context,
  WidgetRef ref,
  Invite invite, {
  required String groupName,
}) async {
  final box = context.findRenderObject();
  final origin = box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(inviteSharerProvider)
        .share(invite, groupName: groupName, origin: origin);
  } on Object {
    await Clipboard.setData(ClipboardData(text: invite.url));
    messenger.showSnackBar(
      const SnackBar(content: Text("Couldn't share, so the link was copied")),
    );
  }
}

/// The invites part of the group hub: "Create invite" (when allowed) and
/// the invites I can see, with status, use count, share, copy and revoke.
class InvitesSection extends ConsumerWidget {
  const new({required this.group, required this.permissions, super.key});

  final Group group;
  final GroupPermissions permissions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invites = ref.watch(invitesProvider(group.id));
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (permissions.canCreateInvite)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonalIcon(
              onPressed: () => unawaited(
                showCreateInviteSheet(
                  context,
                  group: group,
                  permissions: permissions,
                ),
              ),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Create invite'),
            ),
          )
        else
          const Text('Only admins can invite people to this group.'),
        if (!permissions.seesAllInvites) ...[
          const SizedBox(height: 8),
          Text('You see the invites you created.', style: textTheme.bodySmall),
        ],
        const SizedBox(height: 8),
        AsyncValueView(
          value: invites,
          onRetry: () => ref.invalidate(invitesProvider(group.id)),
          data: (invites) => invites.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No invites yet.'),
                )
              : Column(
                  children: [
                    for (final invite in invites)
                      InviteTile(
                        invite: invite,
                        groupName: group.name,
                        showCreator: permissions.seesAllInvites,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// One invite: its code, status, uses and expiry, with Share (while valid),
/// Copy code, and Revoke (when `can_delete`).
class InviteTile extends ConsumerWidget {
  const new({
    required this.invite,
    required this.groupName,
    this.showCreator = false,
    super.key,
  });

  final Invite invite;
  final String groupName;
  final bool showCreator;

  String get _uses {
    final uses = invite.useCount;
    final max = invite.maxUses;
    if (max != null) return '$uses of $max uses';
    return uses == 1 ? '1 use' : '$uses uses';
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(groupsControllerProvider.notifier);
    final confirmed = await showConfirmDialog(
      context,
      title: 'Revoke this invite?',
      message:
          'The code ${InviteCode.format(invite.code)} stops working for '
          "anyone who hasn't used it yet.",
      confirmLabel: 'Revoke',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await runGroupAction(
      context,
      () => controller.revokeInvite(invite.groupId, invite.id),
      success: 'Invite revoked',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final valid = invite.status == InviteStatus.valid;
    final creator = invite.createdBy?.displayName;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    InviteCode.format(invite.code),
                    style: textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                _StatusChip(status: invite.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                _uses,
                if (valid || invite.status == InviteStatus.exhausted)
                  inviteExpiryLabel(invite.expiresAt),
                if (showCreator && creator != null) 'by $creator',
              ].join(' · '),
              style: textTheme.bodySmall,
            ),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              children: [
                if (valid)
                  Builder(
                    builder: (context) => TextButton.icon(
                      onPressed: () => unawaited(
                        shareInvite(context, ref, invite, groupName: groupName),
                      ),
                      icon: const Icon(Icons.share),
                      label: const Text('Share'),
                    ),
                  ),
                if (valid)
                  TextButton.icon(
                    onPressed: () =>
                        unawaited(copyInviteCode(context, invite.code)),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy code'),
                  ),
                if (invite.canDelete && invite.status != InviteStatus.revoked)
                  TextButton.icon(
                    onPressed: () => unawaited(_revoke(context, ref)),
                    icon: const Icon(Icons.block),
                    label: const Text('Revoke'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const new({required this.status});

  final InviteStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final valid = status == InviteStatus.valid;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: valid ? colors.primaryContainer : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          inviteStatusLabel(status),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: valid ? colors.onPrimaryContainer : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// How long a new invite stays valid (`InviteCreate`).
enum InviteExpiry {
  day(24, '1 day'),
  week(168, '7 days'),
  month(720, '30 days'),
  never(null, 'Never');

  new(this.hours, this.label);

  /// `expires_in_hours`, or null for `never_expires`.
  final int? hours;
  final String label;
}

/// Opens the "create invite" sheet and, once created, the dialog to share
/// the new invite.
Future<void> showCreateInviteSheet(
  BuildContext context, {
  required Group group,
  required GroupPermissions permissions,
}) async {
  final invite = await showModalBottomSheet<Invite>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => CreateInviteSheet(
      groupId: group.id,
      canNeverExpire: permissions.canCreateNeverExpiringInvite,
    ),
  );
  if (invite == null || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) =>
        InviteCreatedDialog(invite: invite, groupName: group.name),
  );
}

/// The "create invite" form: expiry (1 day, 7 days, 30 days, or never for
/// admin+) and an optional maximum number of uses (1..100). Pops with the
/// created [Invite].
class CreateInviteSheet extends ConsumerStatefulWidget {
  const new({required this.groupId, required this.canNeverExpire, super.key});

  final String groupId;

  /// Offer "Never" (admin+ only, contract section 7.2).
  final bool canNeverExpire;

  @override
  ConsumerState<CreateInviteSheet> createState() => _CreateInviteSheetState();
}

class _CreateInviteSheetState extends ConsumerState<CreateInviteSheet>
    with ServerErrorsMixin {
  static const _fields = {'max_uses', 'expires_in_hours'};

  static const Map<String, String> _messages = {
    ErrorCodes.forbidden: 'Only admins can create this invite.',
  };

  final _formKey = GlobalKey<FormState>();
  final _maxUses = TextEditingController();
  InviteExpiry _expiry = InviteExpiry.week;
  bool _creating = false;

  @override
  void dispose() {
    _maxUses.dispose();
    super.dispose();
  }

  static String? _validateMaxUses(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final uses = int.tryParse(text);
    if (uses == null || uses < 1 || uses > 100) {
      return 'Enter a number from 1 to 100, or leave it empty.';
    }
    return null;
  }

  Future<void> _create() async {
    clearFormError();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _creating = true);
    final hours = _expiry.hours;
    try {
      final invite = await ref
          .read(groupsControllerProvider.notifier)
          .createInvite(
            widget.groupId,
            InviteCreate(
              maxUses: int.tryParse(_maxUses.text.trim()),
              expiresInHours: hours ?? InviteExpiry.week.hours!,
              neverExpires: hours == null,
            ),
          );
      if (mounted) Navigator.of(context).pop(invite);
    } on ApiException catch (e) {
      if (mounted) showServerError(e, fields: _fields, messages: _messages);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = [
      for (final expiry in InviteExpiry.values)
        if (expiry != InviteExpiry.never || widget.canNeverExpire) expiry,
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('New invite', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (formError case final message?) ...[
              FormMessageBanner(message: message),
              const SizedBox(height: 16),
            ],
            Text(
              'Expires after',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            SegmentedButton<InviteExpiry>(
              showSelectedIcon: false,
              segments: [
                for (final expiry in options)
                  ButtonSegment(value: expiry, label: Text(expiry.label)),
              ],
              selected: {_expiry},
              onSelectionChanged: (selection) =>
                  setState(() => _expiry = selection.single),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _maxUses,
              decoration: const InputDecoration(
                labelText: 'Max uses',
                helperText: 'Leave empty for unlimited',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: _validateMaxUses,
              forceErrorText: serverError('max_uses'),
              onChanged: (_) => clearServerError('max_uses'),
              onFieldSubmitted: (_) => unawaited(_create()),
            ),
            const SizedBox(height: 24),
            SubmitButton(
              label: 'Create invite',
              busy: _creating,
              onPressed: _create,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown after creating an invite: the code as `XXXXX-XXXXX` and the link,
/// with Share and Copy.
class InviteCreatedDialog extends ConsumerWidget {
  const new({required this.invite, required this.groupName, super.key});

  final Invite invite;
  final String groupName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Invite created'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Share the link, or give your friends the code.'),
          const SizedBox(height: 16),
          SelectableText(
            InviteCode.format(invite.code),
            style: textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          SelectableText(
            invite.url,
            style: textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            inviteExpiryLabel(invite.expiresAt),
            style: textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => unawaited(copyInviteCode(context, invite.code)),
          child: const Text('Copy code'),
        ),
        Builder(
          builder: (context) => FilledButton.icon(
            onPressed: () => unawaited(
              shareInvite(context, ref, invite, groupName: groupName),
            ),
            icon: const Icon(Icons.share),
            label: const Text('Share'),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
