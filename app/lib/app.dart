import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/router/app_router.dart';
import 'package:friends/core/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

class FriendsApp extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Friends',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
