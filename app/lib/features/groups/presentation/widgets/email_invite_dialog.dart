import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/forms/field_errors.dart';
import 'package:friends/core/forms/validators.dart';
import 'package:friends/core/widgets/form_widgets.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Asks for an address and emails [invite]'s link to it (contract section
/// 18.5). Snack-bars "Invite sent" when done.
Future<void> showEmailInviteDialog(BuildContext context, Invite invite) async {
  final messenger = ScaffoldMessenger.of(context);
  final sent = context.l10n.inviteEmailSent;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => _EmailInviteDialog(invite: invite),
  );
  if (ok ?? false) messenger.showSnackBar(SnackBar(content: Text(sent)));
}

class _EmailInviteDialog extends ConsumerStatefulWidget {
  const new({required this.invite});

  final Invite invite;

  @override
  ConsumerState<_EmailInviteDialog> createState() => _EmailInviteDialogState();
}

class _EmailInviteDialogState extends ConsumerState<_EmailInviteDialog>
    with ServerErrorsMixin {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    clearFormError();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      await apiCall(
        () => ref
            .read(invitesClientProvider)
            .emailInvite(
              groupId: widget.invite.groupId,
              inviteId: widget.invite.id,
              body: InviteEmail(email: _email.text.trim()),
            ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) showServerError(e, fields: const {'email'});
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.emailInviteTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (formError case final message?) ...[
              FormMessageBanner(message: message),
              const SizedBox(height: 12),
            ],
            Text(l10n.emailInviteHelp),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.email),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              validator: Validators.email,
              forceErrorText: serverError('email'),
              onChanged: (_) => clearServerError('email'),
              onFieldSubmitted: (_) => _send(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: Text(l10n.send),
        ),
      ],
    );
  }
}
