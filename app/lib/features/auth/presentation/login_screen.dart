import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/forms/field_errors.dart';
import 'package:friends/core/forms/validators.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/form_widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Email and password sign-in. On success the router moves on to [from]
/// (or `/`), because the auth state becomes `Authenticated`.
class LoginScreen extends ConsumerStatefulWidget {
  const new({this.from, super.key});

  /// Where to go after signing in.
  final String? from;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with ServerErrorsMixin {
  static const _fields = {'email', 'password'};

  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    clearFormError();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(email: _email.text, password: _password.text);
    } on ApiException catch (e) {
      if (mounted) showServerError(e, fields: _fields);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _goToRegister() => context.go(Routes.registerWith(from: widget.from));

  @override
  Widget build(BuildContext context) {
    final reason = switch (ref.watch(authControllerProvider)) {
      Unauthenticated(:final reason) => reason,
      _ => null,
    };
    final notice = switch (reason) {
      SignOutReason.sessionExpired =>
        'Your session has ended. Please sign in again.',
      SignOutReason.accountDeleted => 'Your account has been deleted.',
      _ => null,
    };
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: FormPage(
        child: AutofillGroup(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.diversity_3, size: 56),
                const SizedBox(height: 16),
                Text(
                  'Welcome back',
                  style: textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (notice != null && formError == null) ...[
                  FormMessageBanner(message: notice, info: true),
                  const SizedBox(height: 16),
                ],
                if (formError case final message?) ...[
                  FormMessageBanner(message: message),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofillHints: const [
                    AutofillHints.email,
                    AutofillHints.username,
                  ],
                  textInputAction: TextInputAction.next,
                  validator: Validators.email,
                  forceErrorText: serverError('email'),
                  onChanged: (_) => clearServerError('email'),
                ),
                const SizedBox(height: 12),
                PasswordFormField(
                  controller: _password,
                  label: 'Password',
                  textInputAction: TextInputAction.done,
                  validator: Validators.currentPassword,
                  forceErrorText: serverError('password'),
                  onChanged: (_) => clearServerError('password'),
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),
                SubmitButton(
                  label: 'Sign in',
                  busy: _submitting,
                  onPressed: _submit,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _submitting ? null : _goToRegister,
                  child: const Text('New here? Create an account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
