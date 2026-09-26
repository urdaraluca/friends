import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/config/env.dart';
import 'package:friends/core/links/open_link.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/features/profile/presentation/widgets/change_password_form.dart';
import 'package:friends/features/profile/presentation/widgets/delete_account_dialog.dart';
import 'package:friends/features/profile/presentation/widgets/profile_form.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// The signed-in user's profile: name, birthday and timezone, password,
/// sessions, and account deletion (required in-app by Apple).
class ProfileScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(
        // Opened directly (a deep link, or after signing in): nothing to pop.
        leading: context.canPop()
            ? null
            : IconButton(
                tooltip: 'Home',
                icon: const Icon(Icons.home_outlined),
                onPressed: () => context.go(Routes.home),
              ),
        title: const Text('Profile'),
      ),
      body: user == null
          ? const LoadingView()
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _Section(
                      title: 'Profile',
                      subtitle: user.email,
                      child: ProfileForm(key: ValueKey(user.id), user: user),
                    ),
                    const _Section(
                      title: 'Password',
                      child: ChangePasswordForm(),
                    ),
                    const _Section(title: 'Sessions', child: _SessionActions()),
                    const _Section(
                      title: 'Delete account',
                      child: _DeleteAccount(),
                    ),
                    ListTile(
                      leading: const Icon(Icons.privacy_tip_outlined),
                      title: const Text('Privacy'),
                      subtitle: const Text('What Friends stores, and why'),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: () =>
                          unawaited(openLink(context, ref, privacyPolicyUrl())),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const new({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: textTheme.titleMedium),
            if (subtitle case final subtitle?)
              Text(subtitle, style: textTheme.bodySmall),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _SessionActions extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_SessionActions> createState() => _SessionActionsState();
}

class _SessionActionsState extends ConsumerState<_SessionActions> {
  bool _busy = false;

  Future<void> _run(Future<void> Function(AuthController auth) action) async {
    setState(() => _busy = true);
    try {
      await action(ref.read(authControllerProvider.notifier));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logoutEverywhere() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out everywhere?'),
        content: const Text(
          'This signs you out on every device, including this one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out everywhere'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await _run((auth) => auth.logoutAll());
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : () => unawaited(_run((a) => a.logout())),
          icon: const Icon(Icons.logout),
          label: const Text('Log out'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => unawaited(_logoutEverywhere()),
          icon: const Icon(Icons.devices),
          label: const Text('Log out everywhere'),
        ),
      ],
    );
  }
}

class _DeleteAccount extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your groups go to another member (or are deleted if you are '
          'alone in them), and your profile is anonymized. What you added '
          'stays, shown as "Deleted user".',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => const DeleteAccountDialog(),
          ),
          icon: const Icon(Icons.delete_forever),
          label: const Text('Delete my account'),
        ),
      ],
    );
  }
}

/// The privacy page, served by the backend next to the web app
/// (`app/web/privacy.html`).
Uri privacyPolicyUrl() => Uri.parse(Env.apiBaseUrl).resolve('/privacy.html');
