import 'dart:async';

import 'package:friends/core/invites/invite_code.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Asks for an invite code, then opens its preview (`/join/<code>`), where
/// the user can join.
Future<void> joinWithCode(BuildContext context) async {
  final code = await showDialog<String>(
    context: context,
    builder: (context) => const JoinWithCodeDialog(),
  );
  if (code != null && context.mounted) {
    unawaited(context.push(Routes.join(code)));
  }
}

/// The "Join with code" dialog. Pops with the normalized code.
///
/// Accepts any spelling, normalized exactly like the server does (contract
/// section 4.7: spaces and dashes stripped, uppercased, I/L→1, O→0), or a
/// pasted `…/join/<code>` link.
class JoinWithCodeDialog extends StatefulWidget {
  const new({super.key});

  @override
  State<JoinWithCodeDialog> createState() => _JoinWithCodeDialogState();
}

class _JoinWithCodeDialogState extends State<JoinWithCodeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  static String? _validate(String? value) {
    if ((value ?? '').trim().isEmpty) return currentL10n.enterInviteCode;
    return InviteCode.parse(value!) == null ? currentL10n.notInviteCode : null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(InviteCode.parse(_code.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.joinWithCode),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _code,
          autofocus: true,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.go,
          decoration: InputDecoration(
            labelText: context.l10n.inviteCode,
            helperText: context.l10n.joinWithCodeHelper,
          ),
          validator: _validate,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(context.l10n.continueLabel),
        ),
      ],
    );
  }
}
