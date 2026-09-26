import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/date_only.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/groups/data/group_providers.dart';
import 'package:friends/features/recap/data/recap_providers.dart';
import 'package:friends/features/recap/domain/recap_period.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// "Your 2026 with Friends" all January, and last month's recap during a
/// month's first week ([recapBannerFor]), until dismissed on this device.
class RecapBanner extends ConsumerWidget {
  const new({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = recapBannerFor(ref.watch(recapClockProvider)());
    if (spec == null) return const SizedBox.shrink();
    final key = recapBannerKey(groupId, spec.period, spec.start);
    final dismissed = ref.watch(dismissedRecapBannersProvider).value;
    if (dismissed == null || dismissed.contains(key)) {
      return const SizedBox.shrink();
    }
    final name = ref.watch(groupProvider(groupId)).value?.name;
    final colors = Theme.of(context).colorScheme;
    final label = periodLabel(spec.period, spec.start);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Card(
        margin: EdgeInsets.zero,
        color: colors.tertiaryContainer,
        child: ListTile(
          leading: Icon(Icons.auto_awesome, color: colors.onTertiaryContainer),
          title: Text(name == null ? 'Your $label' : 'Your $label with $name'),
          subtitle: const Text('Your recap is ready: see the highlights'),
          onTap: () => unawaited(
            context.push(
              Routes.groupRecap(
                groupId,
                period: spec.period.json!,
                start: DateOnly.format(spec.start),
              ),
            ),
          ),
          trailing: IconButton(
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close),
            onPressed: () => unawaited(
              ref.read(dismissedRecapBannersProvider.notifier).dismiss(key),
            ),
          ),
        ),
      ),
    );
  }
}
