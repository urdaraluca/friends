import 'package:friends/core/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

/// A group's emoji on its colour (or its initial when it has no emoji).
class GroupAvatar extends StatelessWidget {
  const new({
    required this.name,
    this.emoji,
    this.color,
    this.radius = 20,
    super.key,
  });

  final String name;
  final String? emoji;

  /// `#RRGGBB`, or null for the theme's colour.
  final String? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = HexColor.tryParse(color) ?? colors.primaryContainer;
    final foreground =
        ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final emoji = this.emoji?.trim() ?? '';
    final trimmedName = name.trim();
    final initial = trimmedName.isEmpty
        ? '?'
        : String.fromCharCode(trimmedName.runes.first).toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: background,
      foregroundColor: foreground,
      child: Text(
        emoji.isEmpty ? initial : emoji,
        style: TextStyle(fontSize: radius * (emoji.isEmpty ? 0.9 : 1)),
      ),
    );
  }
}
