import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/forms/field_errors.dart';
import 'package:friends/core/forms/validators.dart';
import 'package:friends/core/widgets/form_widgets.dart';
import 'package:material_ui/material_ui.dart';

/// Confirms account deletion with the password (`POST /me/deletion`). On
/// success the user is signed out and the router shows the login screen.
class DeleteAccountDialog extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<DeleteAccountDialog>
    with ServerErrorsMixin {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _deleting = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    clearFormError();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _deleting = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .deleteAccount(password: _password.text);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) {
        showServerError(
          e,
          fields: const {'password'},
          codeFields: const {ErrorCodes.wrongPassword: 'password'},
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'This cannot be undone. Enter your password to confirm.',
            ),
            const SizedBox(height: 16),
            if (formError case final message?) ...[
              FormMessageBanner(message: message),
              const SizedBox(height: 12),
            ],
            PasswordFormField(
              controller: _password,
              label: 'Password',
              validator: Validators.currentPassword,
              forceErrorText: serverError('password'),
              onChanged: (_) => clearServerError('password'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          onPressed: _deleting ? null : _delete,
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}
