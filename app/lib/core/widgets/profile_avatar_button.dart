import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// The signed-in user's avatar (or initial) in an app bar; opens the
/// profile.
class ProfileAvatarButton extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final name = user?.displayName.trim() ?? '';
    final avatarUrl = user?.avatarUrl;
    return IconButton(
      tooltip: context.l10n.profile,
      onPressed: () => unawaited(context.push(Routes.profile)),
      icon: CircleAvatar(
        radius: 16,
        foregroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
        onForegroundImageError: avatarUrl == null ? null : (_, _) {},
        child: name.isEmpty
            ? const Icon(Icons.person, size: 18)
            : Text(String.fromCharCode(name.runes.first).toUpperCase()),
      ),
    );
  }
}
