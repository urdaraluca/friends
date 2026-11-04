import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/forms/field_errors.dart';
import 'package:friends/core/forms/validators.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/form_widgets.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// The emailed password-reset link (`/reset-password?token=`, contract
/// section 18.2): a new password, then signing in again (every session ends).
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const new({required this.token, super.key});

  /// The link's token; empty when the link was cut short.
  final String token;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen>
    with ServerErrorsMixin {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _submitting = false;
  bool _done = false;

  /// The server turned the token down: used, expired or unknown.
  bool _rejected = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    clearFormError();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await apiCall(
        () => ref
            .read(publicAuthClientProvider)
            .resetPassword(
              body: PasswordReset(
                token: widget.token,
                newPassword: _password.text,
              ),
            ),
      );
      if (mounted) setState(() => _done = true);
    } on ApiException catch (e) {
      if (e is ProblemException && e.code == ErrorCodes.invalidToken) {
        if (mounted) setState(() => _rejected = true);
      } else if (mounted) {
        showServerError(
          e,
          fields: const {'new_password'},
          codeFields: const {ErrorCodes.weakPassword: 'new_password'},
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final invalid = widget.token.isEmpty || _rejected;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.chooseNewPassword)),
      body: FormPage(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_done) ...[
                FormMessageBanner(message: l10n.passwordResetDone, info: true),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go(Routes.login),
                  child: Text(l10n.signIn),
                ),
              ] else if (invalid) ...[
                FormMessageBanner(message: l10n.resetLinkInvalid),
              ] else ...[
                if (formError case final message?) ...[
                  FormMessageBanner(message: message),
                  const SizedBox(height: 16),
                ],
                PasswordFormField(
                  controller: _password,
                  label: l10n.newPassword,
                  helperText: l10n.passwordHelper,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  validator: Validators.newPassword,
                  forceErrorText: serverError('new_password'),
                  onChanged: (_) => clearServerError('new_password'),
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),
                SubmitButton(
                  label: l10n.setNewPassword,
                  busy: _submitting,
                  onPressed: _submit,
                ),
              ],
              if (!_done && (invalid || formError != null)) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.go(Routes.forgotPassword),
                  child: Text(l10n.requestNewLink),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
