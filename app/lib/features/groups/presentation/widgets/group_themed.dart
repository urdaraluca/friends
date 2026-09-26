import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/theme/app_theme.dart';
import 'package:friends/features/groups/data/group_providers.dart';
import 'package:material_ui/material_ui.dart';

/// Applies the group's colour theme (like `GroupShell`) to a full-screen
/// page opened above the shell: an activity, a form, the categories.
class GroupThemed extends ConsumerWidget {
  const new({required this.groupId, required this.child, super.key});

  final String groupId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = ref.watch(groupProvider(groupId)).value?.color;
    final seed = HexColor.tryParse(color);
    if (seed == null) return child;
    return Theme(
      data: AppTheme.seededFrom(seed, Theme.of(context).brightness),
      child: child,
    );
  }
}
