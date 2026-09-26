import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/config/env.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/features/health/data/health_repository.dart';
import 'package:material_ui/material_ui.dart';

/// API status, for debugging (`/health`, reachable in every auth state).
class HealthScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Server status')),
      body: AsyncValueView(
        value: ref.watch(apiHealthProvider),
        onRetry: () => ref.invalidate(apiHealthProvider),
        data: (health) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline, size: 48),
                const SizedBox(height: 12),
                Text('API ${health.status}', style: textTheme.headlineSmall),
                Text('version ${health.version}'),
                Text('database ${health.db}'),
                const SizedBox(height: 12),
                Text('app ${Env.appEnv}', style: textTheme.bodySmall),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(apiHealthProvider),
                  child: const Text('Check again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
