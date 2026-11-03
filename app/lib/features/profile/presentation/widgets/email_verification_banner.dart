import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// "Confirm your email" with Resend, while my address isn't verified
/// (contract section 18.3). Nothing is blocked without it; only password
/// reset, invites by email and notifications need it.
class EmailVerificationBanner extends ConsumerStatefulWidget {
  const new({this.padding = EdgeInsets.zero, super.key});

  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<EmailVerificationBanner> createState() =>
      _EmailVerificationBannerState();
}

class _EmailVerificationBannerState
    extends ConsumerState<EmailVerificationBanner> {
  bool _busy = false;
  bool _sent = false;

  Future<void> _resend() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      await apiCall(ref.read(usersClientProvider).sendVerificationEmail);
      if (mounted) setState(() => _sent = true);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.verificationEmailSent)),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null || user.emailVerified) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Padding(
      padding: widget.padding,
      child: Card(
        margin: EdgeInsets.zero,
        color: colors.secondaryContainer,
        child: ListTile(
          leading: Icon(
            Icons.mark_email_unread_outlined,
            color: colors.onSecondaryContainer,
          ),
          title: Text(l10n.confirmYourEmail),
          subtitle: Text(
            _sent ? l10n.checkInboxFor(user.email) : l10n.confirmEmailWhy,
          ),
          trailing: TextButton(
            onPressed: _busy ? null : () => unawaited(_resend()),
            child: Text(_sent ? l10n.resend : l10n.sendLink),
          ),
        ),
      ),
    );
  }
}
