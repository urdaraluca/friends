import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/forms/field_errors.dart';
import 'package:friends/core/forms/validators.dart';
import 'package:friends/core/widgets/form_widgets.dart';
import 'package:material_ui/material_ui.dart';

/// `POST /me/password`. Other devices are signed out; this one keeps going
/// with the returned tokens.
class ChangePasswordForm extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends ConsumerState<ChangePasswordForm>
    with ServerErrorsMixin {
  static const _fields = {'current_password', 'new_password'};

  /// `wrong_password` names its field; `weak_password` doesn't.
  static const Map<String, String> _codeFields = {
    ErrorCodes.wrongPassword: 'current_password',
    ErrorCodes.weakPassword: 'new_password',
  };

  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    clearFormError();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .changePassword(
            currentPassword: _current.text,
            newPassword: _new.text,
          );
      if (!mounted) return;
      _current.clear();
      _new.clear();
      _formKey.currentState!.reset();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password changed. Your other devices have been signed out.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        showServerError(e, fields: _fields, codeFields: _codeFields);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (formError case final message?) ...[
              FormMessageBanner(message: message),
              const SizedBox(height: 12),
            ],
            PasswordFormField(
              controller: _current,
              label: 'Current password',
              textInputAction: TextInputAction.next,
              validator: Validators.currentPassword,
              forceErrorText: serverError('current_password'),
              onChanged: (_) => clearServerError('current_password'),
            ),
            const SizedBox(height: 12),
            PasswordFormField(
              controller: _new,
              label: 'New password',
              helperText: 'At least 10 characters',
              autofillHints: const [AutofillHints.newPassword],
              validator: Validators.newPassword,
              forceErrorText: serverError('new_password'),
              onChanged: (_) => clearServerError('new_password'),
            ),
            const SizedBox(height: 16),
            SubmitButton(
              label: 'Change password',
              busy: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
