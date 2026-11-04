import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/push/web_push.dart';
import 'package:friends/features/notifications/data/push_controller.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Turns push on in this browser (contract section 18.6); snack-bars the
/// outcome. Shared by the prompt card and the settings switch.
Future<void> enablePush(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    final on = await ref.read(pushControllerProvider.notifier).enable();
    messenger.showSnackBar(
      SnackBar(content: Text(on ? l10n.pushEnabled : l10n.pushBlocked)),
    );
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
  }
}

/// "Get notified" on the groups list, until push is on here, blocked, or the
/// card is dismissed.
class PushPrompt extends ConsumerWidget {
  const new({this.padding = EdgeInsets.zero, super.key});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final push = ref.watch(pushControllerProvider).value;
    final dismissed = ref.watch(pushPromptDismissedProvider).value ?? true;
    if (push == null ||
        !push.supported ||
        push.enabled ||
        push.permission == PushPermission.denied ||
        dismissed) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Padding(
      padding: padding,
      child: Card(
        margin: EdgeInsets.zero,
        color: colors.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.notifications_active_outlined,
                    color: colors.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.pushPromptTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(l10n.pushPromptBody),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => unawaited(
                      ref.read(pushPromptDismissedProvider.notifier).dismiss(),
                    ),
                    child: Text(l10n.notNow),
                  ),
                  FilledButton(
                    onPressed: () => unawaited(enablePush(context, ref)),
                    child: Text(l10n.turnOn),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
