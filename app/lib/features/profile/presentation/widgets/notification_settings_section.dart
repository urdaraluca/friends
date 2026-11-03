import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/push/web_push.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/features/notifications/data/notification_providers.dart';
import 'package:friends/features/notifications/data/push_controller.dart';
import 'package:friends/features/notifications/presentation/push_prompt.dart';
import 'package:friends/features/profile/presentation/widgets/email_verification_banner.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Notifications (contract section 18.4): push in this browser first, which
/// kinds, and email as an opt-in fallback.
class NotificationSettingsSection extends ConsumerWidget {
  const new({super.key});

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    NotificationSettings next,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(notificationSettingsControllerProvider.notifier)
          .save(next);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final verified = ref.watch(currentUserProvider)?.emailVerified ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PushSwitch(),
        const Divider(),
        AsyncValueView(
          value: ref.watch(notificationSettingsControllerProvider),
          onRetry: () => ref.invalidate(notificationSettingsControllerProvider),
          data: (settings) {
            Widget kind(
              String title,
              String help, {
              required bool value,
              required NotificationSettings Function({required bool on}) apply,
            }) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(title),
              subtitle: Text(help),
              value: value,
              onChanged: (on) => unawaited(_save(context, ref, apply(on: on))),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                kind(
                  l10n.notifyPolls,
                  l10n.notifyPollsHelp,
                  value: settings.polls,
                  apply: ({required on}) => settings.copyWith(polls: on),
                ),
                kind(
                  l10n.notifyWheel,
                  l10n.notifyWheelHelp,
                  value: settings.wheel,
                  apply: ({required on}) => settings.copyWith(wheel: on),
                ),
                kind(
                  l10n.notifyReminders,
                  l10n.notifyRemindersHelp,
                  value: settings.reminders,
                  apply: ({required on}) => settings.copyWith(reminders: on),
                ),
                kind(
                  l10n.notifyPlans,
                  l10n.notifyPlansHelp,
                  value: settings.plans,
                  apply: ({required on}) => settings.copyWith(plans: on),
                ),
                kind(
                  l10n.notifyMembers,
                  l10n.notifyMembersHelp,
                  value: settings.members,
                  apply: ({required on}) => settings.copyWith(members: on),
                ),
                const Divider(),
                kind(
                  l10n.notifyEmail,
                  l10n.notifyEmailHelp,
                  value: settings.email,
                  apply: ({required on}) => settings.copyWith(email: on),
                ),
                if (settings.email && !verified) ...[
                  const SizedBox(height: 8),
                  const EmailVerificationBanner(),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PushSwitch extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final push = ref.watch(pushControllerProvider).value;
    if (push == null || !push.supported) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.notifications_off_outlined),
        title: Text(l10n.pushHere),
        subtitle: Text(l10n.pushUnavailable),
      );
    }
    final blocked = push.permission == PushPermission.denied;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.notifications_active_outlined),
      title: Text(l10n.pushHere),
      subtitle: Text(blocked ? l10n.pushBlocked : l10n.pushHereHelp),
      value: push.enabled,
      onChanged: blocked
          ? null
          : (on) => unawaited(
              on
                  ? enablePush(context, ref)
                  : ref.read(pushControllerProvider.notifier).disable(),
            ),
    );
  }
}
