import 'package:friends/core/widgets/coming_soon_view.dart';
import 'package:material_ui/material_ui.dart';

/// PLACEHOLDER for the group's Backlog tab (`/groups/:groupId/backlog`).
///
/// The backlog milestone replaces this widget (and the route builder in
/// `core/router/app_router.dart` that creates it) with the real screen.
/// It is shown inside `GroupShell`, which provides the app bar and the
/// bottom navigation.
class BacklogPlaceholderScreen extends StatelessWidget {
  const new({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    return const ComingSoonView(
      icon: Icons.checklist,
      title: 'Backlog',
      message: 'Ideas for things to do together will show up here.',
    );
  }
}
