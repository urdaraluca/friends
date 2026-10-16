import 'package:friends/features/books/domain/book_status.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Five stars showing [value] (1 to 5, or null for none).
///
/// With [onChanged], each star is a button: tapping a star sets that many,
/// and tapping the current one clears the rating (null).
class StarRating extends StatelessWidget {
  const new({required this.value, this.onChanged, this.size = 32, super.key});

  final int? value;
  final ValueChanged<int?>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final value = this.value ?? 0;
    final onChanged = this.onChanged;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var stars = 1; stars <= 5; stars++)
          if (onChanged == null)
            Icon(
              stars <= value ? Icons.star : Icons.star_border,
              size: size,
              color: color,
            )
          else
            IconButton(
              key: ValueKey('star-$stars'),
              tooltip: context.l10n.rateStars(stars),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tight(Size.square(size + 8)),
              iconSize: size,
              isSelected: stars <= value,
              icon: Icon(Icons.star_border, color: color),
              selectedIcon: Icon(Icons.star, color: color),
              onPressed: () => onChanged(stars == value ? null : stars),
            ),
      ],
    );
  }
}

/// "★ 4.3 · 6 ratings", or "No ratings yet".
class RatingSummary extends StatelessWidget {
  const new({
    required this.average,
    required this.count,
    this.style,
    super.key,
  });

  final num? average;
  final int count;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final average = this.average;
    final l10n = context.l10n;
    if (average == null || count == 0) {
      return Text(l10n.noRatingsYet, style: style);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.star,
          size: (style?.fontSize ?? 14) + 2,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            l10n.ratingSummary(formatRating(average), count),
            style: style,
          ),
        ),
      ],
    );
  }
}
