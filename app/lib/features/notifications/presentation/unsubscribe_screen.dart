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
import 'package:friends/features/notifications/data/notification_providers.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// A notification email's unsubscribe link (`/unsubscribe?token=`, contract
/// section 18.4): turns that kind of email off as soon as it opens.
class UnsubscribeScreen extends ConsumerStatefulWidget {
  const new({required this.token, super.key});

  final String token;

  @override
  ConsumerState<UnsubscribeScreen> createState() => _UnsubscribeScreenState();
}

class _UnsubscribeScreenState extends ConsumerState<UnsubscribeScreen> {
  /// Null while working; then the message to show.
  String? _message;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    unawaited(_unsubscribe());
  }

  Future<void> _unsubscribe() async {
    final l10n = currentL10n;
    try {
      final result = await apiCall(
        () => ref
            .read(publicNotificationsClientProvider)
            .unsubscribe(token: widget.token),
      );
      ref.invalidate(notificationSettingsControllerProvider);
      if (!mounted) return;
      setState(() {
        _ok = true;
        _message = l10n.unsubscribed(notificationKindLabel(result.kind));
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _message = friendlyErrorMessage(
          e,
          messages: {ErrorCodes.invalidToken: l10n.unsubscribeLinkInvalid},
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final signedIn = ref.watch(currentUserProvider) != null;
    final message = _message;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notifications)),
      body: FormPage(
        child: message == null
            ? const LoadingView()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormMessageBanner(message: message, info: _ok),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () =>
                        context.go(signedIn ? Routes.profile : Routes.login),
                    child: Text(
                      signedIn ? l10n.notificationSettingsLink : l10n.signIn,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// "new polls", "wheel results", "reminders", for sentences.
String notificationKindLabel(NotificationKind kind) {
  final l10n = currentL10n;
  return switch (kind) {
    NotificationKind.polls => l10n.notifyPollsShort,
    NotificationKind.wheel => l10n.notifyWheelShort,
    NotificationKind.reminders => l10n.notifyRemindersShort,
    NotificationKind.members => l10n.notifyMembersShort,
    NotificationKind.plans => l10n.notifyPlansShort,
    NotificationKind.$unknown => l10n.emailNotifications,
  };
}
