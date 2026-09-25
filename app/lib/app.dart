import 'package:friends/core/theme/app_theme.dart';
import 'package:friends/features/health/presentation/health_screen.dart';
import 'package:material_ui/material_ui.dart';

class FriendsApp extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Friends',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const HealthScreen(),
    );
  }
}
