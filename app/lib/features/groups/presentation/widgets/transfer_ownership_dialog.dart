import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/core/widgets/form_widgets.dart';
import 'package:friends/features/groups/data/group_providers.dart';
import 'package:friends/features/groups/data/groups_controller.dart';
import 'package:friends/features/groups/presentation/widgets/group_action.dart';
import 'package:friends/features/groups/presentation/widgets/role_badge.dart';
import 'package:material_ui/material_ui.dart';

/// The transfer-ownership flow: pick another member, confirm, and they
/// become the owner (I become an admin).
///
/// With [leaving] (the owner tried to leave and got `409
/// owner_must_transfer`), I also leave once the transfer is done. Resolves
/// to true when everything worked.
Future<bool> showTransferOwnershipDialog(
  BuildContext context, {
  required String groupId,
  required String groupName,
  bool leaving = false,
}) async {
  final done = await showDialog<bool>(
    context: context,
    builder: (context) => TransferOwnershipDialog(
      groupId: groupId,
      groupName: groupName,
      leaving: leaving,
    ),
  );
  return done ?? false;
}

class TransferOwnershipDialog extends ConsumerStatefulWidget {
  const new({
    required this.groupId,
    required this.groupName,
    this.leaving = false,
    super.key,
  });

  final String groupId;
  final String groupName;
  final bool leaving;

  @override
  ConsumerState<TransferOwnershipDialog> createState() =>
      _TransferOwnershipDialogState();
}

class _TransferOwnershipDialogState
    extends ConsumerState<TransferOwnershipDialog> {
  String? _selected;
  bool _busy = false;
  bool _transferred = false;
  String? _error;

  Future<void> _submit() async {
    final userId = _selected;
    if (userId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(groupsControllerProvider.notifier);
    try {
      // After a transfer that worked and a leave that didn't, Retry only
      // leaves: I'm no longer the owner.
      if (!_transferred) {
        await controller.transferOwnership(widget.groupId, userId);
        _transferred = true;
      }
      if (widget.leaving) await controller.leave(widget.groupId);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyErrorMessage(e, messages: groupErrorMessages);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserIdProvider);
    final members = ref.watch(membersProvider(widget.groupId));
    return AlertDialog(
      title: Text(widget.leaving ? 'Choose a new owner' : 'Transfer ownership'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.leaving
                    ? 'You own ${widget.groupName}. Choose who takes over, '
                          'then you leave the group.'
                    : 'The new owner can delete ${widget.groupName} and '
                          'change roles. You become an admin.',
              ),
              const SizedBox(height: 12),
              if (_error case final error?) ...[
                FormMessageBanner(message: error),
                const SizedBox(height: 12),
              ],
              AsyncValueView(
                value: members,
                onRetry: () => ref.invalidate(membersProvider(widget.groupId)),
                data: (members) {
                  final candidates = [
                    for (final member in members)
                      if (member.user.id != me) member,
                  ];
                  if (candidates.isEmpty) {
                    return const Text(
                      "There's nobody else in the group to take over.",
                    );
                  }
                  return RadioGroup<String>(
                    groupValue: _selected,
                    onChanged: (value) {
                      if (!_busy && !_transferred) {
                        setState(() => _selected = value);
                      }
                    },
                    child: Column(
                      children: [
                        for (final member in candidates)
                          RadioListTile<String>(
                            value: member.user.id,
                            contentPadding: EdgeInsets.zero,
                            title: Text(member.user.displayName),
                            secondary: RoleBadge(member.role),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected == null || _busy ? null : _submit,
          child: Text(widget.leaving ? 'Transfer and leave' : 'Transfer'),
        ),
      ],
    );
  }
}
