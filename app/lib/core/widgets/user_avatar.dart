import 'package:friends/core/api/generated/export.dart';
import 'package:material_ui/material_ui.dart';

/// A user's avatar: their picture when they set one, else their initial.
class UserAvatar extends StatelessWidget {
  const new({required this.user, this.radius = 16, super.key});

  final UserPublic user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final name = user.displayName.trim();
    final initial = name.isEmpty
        ? '?'
        : String.fromCharCode(name.runes.first).toUpperCase();
    final url = user.avatarUrl;
    return Tooltip(
      message: user.displayName,
      child: CircleAvatar(
        radius: radius,
        foregroundImage: url == null ? null : NetworkImage(url),
        child: Text(initial, style: TextStyle(fontSize: radius * 0.9)),
      ),
    );
  }
}

/// Up to [max] overlapping avatars, then "+N".
class AvatarStack extends StatelessWidget {
  const new({required this.users, this.max = 5, this.radius = 14, super.key});

  final List<UserPublic> users;
  final int max;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final shown = users.take(max).toList();
    final extra = users.length - shown.length;
    final step = radius * 1.4;
    final background = Theme.of(context).colorScheme.surface;
    return Semantics(
      label: users.map((u) => u.displayName).join(', '),
      child: SizedBox(
        height: radius * 2 + 4,
        width: shown.isEmpty ? 0 : step * (shown.length - 1) + radius * 2 + 4,
        child: Stack(
          children: [
            for (final (index, user) in shown.indexed)
              Positioned(
                left: step * index,
                child: CircleAvatar(
                  radius: radius + 2,
                  backgroundColor: background,
                  child: UserAvatar(user: user, radius: radius),
                ),
              ),
          ],
        ),
      ),
    ).withExtra(extra, context);
  }
}

extension on Widget {
  Widget withExtra(int extra, BuildContext context) {
    if (extra <= 0) return this;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        this,
        const SizedBox(width: 4),
        Text('+$extra', style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}
