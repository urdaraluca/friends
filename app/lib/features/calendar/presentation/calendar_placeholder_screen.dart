import 'package:friends/core/widgets/coming_soon_view.dart';
import 'package:material_ui/material_ui.dart';

/// PLACEHOLDER for the group's Calendar tab (`/groups/:groupId/calendar`).
///
/// The calendar milestone replaces this widget (and the route builder in
/// `core/router/app_router.dart` that creates it) with the real screen.
/// It is shown inside `GroupShell`, which provides the app bar and the
/// bottom navigation.
class CalendarPlaceholderScreen extends StatelessWidget {
  const new({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    return const ComingSoonView(
      icon: Icons.calendar_month,
      title: 'Calendar',
      message: 'Plans and birthdays will show up here.',
    );
  }
}
