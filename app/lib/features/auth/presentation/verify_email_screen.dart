import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/core/widgets/form_widgets.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// The emailed verification link (`/verify-email?token=`, contract section
/// 18.3): confirms the address as soon as it opens, signed in or not.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const new({required this.token, super.key});

  final String token;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  /// Null while confirming; then the error message, or '' on success.
  String? _result;

  @override
  void initState() {
    super.initState();
    unawaited(_verify());
  }

  Future<void> _verify() async {
    final invalid = currentL10n.verifyLinkInvalid;
    if (widget.token.isEmpty) {
      setState(() => _result = invalid);
      return;
    }
    try {
      await apiCall(
        () => ref
            .read(publicAuthClientProvider)
            .verifyEmail(body: EmailVerification(token: widget.token)),
      );
      await ref.read(authControllerProvider.notifier).reloadMe();
      if (mounted) setState(() => _result = '');
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _result = friendlyErrorMessage(
            e,
            messages: {ErrorCodes.invalidToken: invalid},
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final signedIn = ref.watch(currentUserProvider) != null;
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.verifyEmailTitle)),
      body: FormPage(
        child: result == null
            ? const LoadingView()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormMessageBanner(
                    message: result.isEmpty ? l10n.emailVerified : result,
                    info: result.isEmpty,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () =>
                        context.go(signedIn ? Routes.home : Routes.login),
                    child: Text(signedIn ? l10n.continueToApp : l10n.signIn),
                  ),
                ],
              ),
      ),
    );
  }
}
