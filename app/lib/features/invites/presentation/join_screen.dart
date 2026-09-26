import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/invites/invite_code.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/form_widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Public landing page of an invite link (`/join/:code`).
///
/// A placeholder until M5 adds the invite preview and "Join": signed-out
/// visitors can already create an account with the code pre-filled, or sign
/// in and come back here.
class JoinScreen extends ConsumerWidget {
  const new({required this.code, super.key});

  /// The code from the link, in any spelling.
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final normalized = InviteCode.parse(code);
    final signedIn = ref.watch(currentUserIdProvider) != null;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Invite')),
      body: FormPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.mail_outline, size: 56),
            const SizedBox(height: 16),
            Text(
              normalized == null
                  ? "This invite link doesn't look right."
                  : "You've been invited to a group on Friends",
              style: textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (normalized != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                InviteCode.format(normalized),
                style: textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            if (signedIn)
              FilledButton(
                onPressed: () => context.go(Routes.home),
                child: const Text('Open Friends'),
              )
            else ...[
              FilledButton(
                onPressed: () =>
                    context.go(Routes.registerWith(invite: normalized ?? code)),
                child: const Text('Create account'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () =>
                    context.go(Routes.loginWith(from: Routes.join(code))),
                child: const Text('I already have an account'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
