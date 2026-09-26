import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/forms/field_errors.dart';
import 'package:friends/core/forms/validators.dart';
import 'package:friends/core/invites/invite_code.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/form_widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Account creation. Registration is invite-only by default, so the form
/// takes an optional invite code (any spelling, or a pasted `…/join/<code>`
/// link), normalized like the server does (contract section 4.7).
class RegisterScreen extends ConsumerStatefulWidget {
  const new({this.from, this.invite, super.key});

  /// Where to go after registering.
  final String? from;

  /// Pre-fills the invite code.
  final String? invite;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen>
    with ServerErrorsMixin {
  static const _fields = {'display_name', 'email', 'password', 'invite_code'};

  /// Codes that concern one field but come without `errors[]`.
  static const Map<String, String> _codeFields = {
    ErrorCodes.emailTaken: 'email',
    ErrorCodes.weakPassword: 'password',
    ErrorCodes.notFound: 'invite_code',
    ErrorCodes.inviteExpired: 'invite_code',
    ErrorCodes.inviteRevoked: 'invite_code',
    ErrorCodes.inviteExhausted: 'invite_code',
    ErrorCodes.limitReached: 'invite_code',
  };

  static const Map<String, String> _messages = {
    ErrorCodes.notFound: "We couldn't find this invite code.",
    ErrorCodes.limitReached: 'This group is full.',
  };

  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  late final TextEditingController _inviteCode;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _inviteCode = TextEditingController(text: _initialInviteCode());
  }

  String _initialInviteCode() {
    final raw = widget.invite ?? widget.from;
    final code = raw == null ? null : InviteCode.parse(raw);
    return code == null ? '' : InviteCode.format(code);
  }

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    _inviteCode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    clearFormError();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      // Once signed in, the router moves on to `from` (or `/`).
      // M5: when the returned session.joinedGroup is set, open that group.
      await ref
          .read(authControllerProvider.notifier)
          .register(
            displayName: _displayName.text,
            email: _email.text,
            password: _password.text,
            inviteCode: _inviteCode.text,
          );
    } on ApiException catch (e) {
      if (mounted) {
        showServerError(
          e,
          fields: _fields,
          codeFields: _codeFields,
          messages: _messages,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: FormPage(
        child: AutofillGroup(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Create your account',
                  style: textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (formError case final message?) ...[
                  FormMessageBanner(message: message),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _displayName,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    helperText: 'How your friends see you',
                  ),
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  textInputAction: TextInputAction.next,
                  validator: Validators.required('a display name', max: 50),
                  forceErrorText: serverError('display_name'),
                  onChanged: (_) => clearServerError('display_name'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  validator: Validators.email,
                  forceErrorText: serverError('email'),
                  onChanged: (_) => clearServerError('email'),
                ),
                const SizedBox(height: 12),
                PasswordFormField(
                  controller: _password,
                  label: 'Password',
                  helperText: 'At least 10 characters',
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  validator: Validators.newPassword,
                  forceErrorText: serverError('password'),
                  onChanged: (_) => clearServerError('password'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _inviteCode,
                  decoration: const InputDecoration(
                    labelText: 'Invite code',
                    helperText: 'From your invite link, e.g. ABCDE-12345',
                  ),
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  validator: Validators.optionalInviteCode,
                  forceErrorText: serverError('invite_code'),
                  onChanged: (_) => clearServerError('invite_code'),
                  onFieldSubmitted: (_) => unawaited(_submit()),
                ),
                const SizedBox(height: 24),
                SubmitButton(
                  label: 'Create account',
                  busy: _submitting,
                  onPressed: _submit,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () => context.go(Routes.loginWith(from: widget.from)),
                  child: const Text('Already have an account? Sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
