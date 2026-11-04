import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/forms/field_errors.dart';
import 'package:friends/core/forms/validators.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/form_widgets.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// "Forgot password?": asks for a reset link by email (contract section
/// 18.2). The answer never says whether the address has an account.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen>
    with ServerErrorsMixin {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _submitting = false;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
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
            .requestPasswordReset(
              body: PasswordResetRequest(email: _email.text.trim()),
            ),
      );
      if (mounted) setState(() => _sent = true);
    } on ApiException catch (e) {
      if (mounted) showServerError(e, fields: const {'email'});
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.forgotPasswordTitle)),
      body: FormPage(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_sent) ...[
                FormMessageBanner(message: l10n.resetLinkSent, info: true),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go(Routes.login),
                  child: Text(l10n.backToSignIn),
                ),
              ] else ...[
                Text(l10n.forgotPasswordHelp, style: textTheme.bodyMedium),
                const SizedBox(height: 16),
                if (formError case final message?) ...[
                  FormMessageBanner(message: message),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _email,
                  decoration: InputDecoration(labelText: l10n.email),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.done,
                  validator: Validators.email,
                  forceErrorText: serverError('email'),
                  onChanged: (_) => clearServerError('email'),
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),
                SubmitButton(
                  label: l10n.sendResetLink,
                  busy: _submitting,
                  onPressed: _submit,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
