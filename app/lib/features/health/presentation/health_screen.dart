import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/config/env.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/features/health/data/health_repository.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// API status, for debugging (`/health`, reachable in every auth state).
class HealthScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.serverStatus)),
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
                Text(
                  context.l10n.apiStatus(health.status.toString()),
                  style: textTheme.headlineSmall,
                ),
                Text(context.l10n.versionLabel(health.version)),
                Text(context.l10n.databaseLabel(health.db.toString())),
                const SizedBox(height: 12),
                Text(
                  context.l10n.appEnvLabel(Env.appEnv),
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(apiHealthProvider),
                  child: Text(context.l10n.checkAgain),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
