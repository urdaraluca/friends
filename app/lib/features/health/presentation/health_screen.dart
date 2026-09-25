import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/features/health/data/health_repository.dart';
import 'package:material_ui/material_ui.dart';

class HealthScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(apiHealthProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Friends')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: switch (health) {
            AsyncData(:final value) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline, size: 48),
                const SizedBox(height: 12),
                Text('API ok', style: textTheme.headlineSmall),
                Text('version ${value.version}'),
              ],
            ),
            AsyncError(:final error) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48),
                const SizedBox(height: 12),
                Text("Can't reach the API", style: textTheme.headlineSmall),
                Text('$error', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(apiHealthProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
            _ => const CircularProgressIndicator(),
          },
        ),
      ),
    );
  }
}
