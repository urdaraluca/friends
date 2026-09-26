import 'package:friends/core/theme/app_theme.dart';
import 'package:friends/features/backlog/domain/category_index.dart';
import 'package:material_ui/material_ui.dart';

/// The icon keys the app knows (contract section 6.5). Anything else is shown
/// as given (an emoji) or as a default icon.
const Map<String, IconData> categoryIcons = {
  'movie': Icons.movie_outlined,
  'food': Icons.restaurant,
  'outdoors': Icons.park_outlined,
  'games': Icons.sports_esports_outlined,
  'trips': Icons.flight_takeoff,
  'culture': Icons.theater_comedy_outlined,
  'sports': Icons.sports_soccer,
  'music': Icons.music_note_outlined,
  'party': Icons.celebration_outlined,
  'home': Icons.home_outlined,
  'star': Icons.star_outline,
};

/// A category's icon: a known key, an emoji, or a default.
class CategoryIcon extends StatelessWidget {
  const new({required this.icon, this.color, this.size = 20, super.key});

  final String? icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final key = icon?.trim();
    if (key != null && categoryIcons.containsKey(key)) {
      return Icon(categoryIcons[key], color: color, size: size);
    }
    if (key != null && key.isNotEmpty) {
      return SizedBox.square(
        dimension: size + 4,
        child: Center(
          child: Text(key, style: TextStyle(fontSize: size * 0.9)),
        ),
      );
    }
    return Icon(Icons.label_outline, color: color, size: size);
  }
}

/// A small dot in a category's colour.
class ColorDot extends StatelessWidget {
  const new({required this.color, this.size = 10, super.key});

  final String? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fill =
        HexColor.tryParse(color) ?? Theme.of(context).colorScheme.outline;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
    );
  }
}

/// A category's colour dot and name (its path for a subcategory), or
/// "Uncategorised".
class CategoryLabel extends StatelessWidget {
  const new({
    required this.index,
    required this.categoryId,
    this.style,
    super.key,
  });

  final CategoryIndex index;
  final String? categoryId;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final name = index.path(categoryId);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ColorDot(color: index.color(categoryId)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            name ?? 'Uncategorised',
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}
