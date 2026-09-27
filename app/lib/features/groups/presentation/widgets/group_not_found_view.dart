import 'package:friends/core/router/routes.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Shown when a group endpoint answers 404: I'm not a member (any more), or
/// the group was deleted (contract section 7.1).
class GroupNotFoundView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.group_off, size: 56),
            const SizedBox(height: 16),
            Text(
              context.l10n.groupNotFound,
              style: textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(context.l10n.groupNotFoundHelp, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go(Routes.groups),
              child: Text(context.l10n.backToMyGroups),
            ),
          ],
        ),
      ),
    );
  }
}

/// [GroupNotFoundView] as a page of its own.
class GroupNotFoundScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: const GroupNotFoundView(),
    );
  }
}
