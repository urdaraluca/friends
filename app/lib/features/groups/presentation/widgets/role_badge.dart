import 'package:friends/core/api/generated/export.dart';
import 'package:friends/features/groups/domain/group_permissions.dart';
import 'package:material_ui/material_ui.dart';

/// A small "Owner" / "Admin" / "Member" label.
class RoleBadge extends StatelessWidget {
  const new(this.role, {super.key});

  final Role role;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground) = switch (role) {
      Role.owner => (colors.primary, colors.onPrimary),
      Role.admin => (colors.secondaryContainer, colors.onSecondaryContainer),
      Role.member || Role.$unknown => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          role.label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: foreground),
        ),
      ),
    );
  }
}
