import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Shown while the session is restored. When restoring fails without ending
/// the session (offline, server down), it offers Retry; the router leaves
/// this screen as soon as the auth state is known.
class SplashScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final error = switch (auth) {
      AuthUnknown(:final error) => error,
      _ => null,
    };
    return Scaffold(
      body: SafeArea(
        child: error == null
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.diversity_3, size: 64),
                    SizedBox(height: 24),
                    CircularProgressIndicator(),
                  ],
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: ErrorView(
                      error: error,
                      onRetry: () => unawaited(
                        ref.read(authControllerProvider.notifier).restore(),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push(Routes.health),
                    child: const Text('Server status'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
      ),
    );
  }
}
