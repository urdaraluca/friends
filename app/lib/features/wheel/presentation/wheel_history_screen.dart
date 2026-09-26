import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/features/backlog/presentation/widgets/category_visuals.dart';
import 'package:friends/features/groups/presentation/widgets/group_themed.dart';
import 'package:friends/features/wheel/data/wheel_providers.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// Past spins of a group (`/groups/:groupId/wheel/history`), newest first:
/// who spun, when, the result, whether it was accepted, and how many ideas
/// were on the wheel. Tap one for its snapshot.
class WheelHistoryScreen extends ConsumerWidget {
  const new({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = spinHistoryProvider(groupId);
    final history = ref.watch(provider);
    return GroupThemed(
      groupId: groupId,
      child: Scaffold(
        appBar: AppBar(title: const Text('Wheel history')),
        body: AsyncValueView(
          value: history,
          onRetry: () => ref.invalidate(provider),
          data: (list) {
            if (list.items.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No spins yet. Spin the wheel when the group can’t decide.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () => settled([ref.refresh(provider.future)]),
              child: ListView.builder(
                itemCount: list.items.length + (list.hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= list.items.length) {
                    scheduleMicrotask(
                      () => unawaited(ref.read(provider.notifier).loadMore()),
                    );
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return SpinTile(spin: list.items[index]);
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One past spin.
class SpinTile extends StatelessWidget {
  const new({required this.spin, super.key});

  final WheelSpin spin;

  @override
  Widget build(BuildContext context) {
    final when = DateFormat('EEE d MMM, HH:mm')
        .format(spin.createdAt.toLocal());
    final who = spin.spunBy?.displayName ?? 'Someone';
    final count = spin.candidates.length;
    return ListTile(
      leading: ColorDot(color: spin.result.color, size: 14),
      title: Text(spin.result.title),
      subtitle: Text('$who spun · $when · $count ideas'),
      trailing: spin.acceptedAt != null
          ? const Chip(
              label: Text('Accepted'),
              visualDensity: VisualDensity.compact,
            )
          : null,
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => _SnapshotDialog(spin: spin),
      ),
    );
  }
}

class _SnapshotDialog extends StatelessWidget {
  const new({required this.spin});

  final WheelSpin spin;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('On the wheel'),
      content: SizedBox(
        width: 360,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final (index, candidate) in spin.candidates.indexed)
              ListTile(
                dense: true,
                leading: ColorDot(color: candidate.color),
                title: Text(
                  candidate.title,
                  style: index == spin.resultIndex
                      ? const TextStyle(fontWeight: FontWeight.bold)
                      : null,
                ),
                trailing: index == spin.resultIndex
                    ? const Icon(Icons.emoji_events)
                    : null,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
