import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/widgets/user_avatar.dart';
import 'package:friends/features/backlog/domain/activity_rules.dart';
import 'package:friends/features/backlog/domain/category_index.dart';
import 'package:friends/features/backlog/domain/field_values.dart';
import 'package:friends/features/backlog/presentation/widgets/category_visuals.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// One backlog item (`ActivitySummary`): title, category, status, owner, due
/// date, cost, interest, the category's card attributes, and badges for an
/// unanswered poll ("Vote") and the next scheduled occurrence.
class ActivityCard extends StatelessWidget {
  const new({
    required this.activity,
    required this.categories,
    required this.onTap,
    required this.onToggleInterest,
    super.key,
  });

  final ActivitySummary activity;
  final CategoryIndex categories;
  final VoidCallback onTap;

  /// Toggles my interest (the parent updates the card optimistically).
  final VoidCallback onToggleInterest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final muted = textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final cost = costLabel(
      cost: activity.estimatedCost,
      currency: activity.currency,
      perPerson: activity.costPerPerson,
    );
    final next = activity.nextOccurrence;
    final details = <Widget>[
      if (activity.dueDate case final due?)
        _Detail(icon: Icons.flag_outlined, text: 'By ${_date(due)}'),
      if (cost != null) _Detail(icon: Icons.payments_outlined, text: cost),
      if (next != null)
        _Detail(icon: Icons.event, text: nextOccurrenceLabel(next)),
    ];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            activity.title,
                            style: textTheme.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (activity.myUnvotedPollCount > 0) ...[
                          const SizedBox(width: 8),
                          const VoteBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        CategoryLabel(
                          index: categories,
                          categoryId: activity.categoryId,
                          style: muted,
                        ),
                        StatusChip(status: activity.status, dense: true),
                      ],
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 12, runSpacing: 4, children: details),
                    ],
                    if (activity.cardAttributes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final attribute in activity.cardAttributes)
                            CardAttributeChip(attribute: attribute),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Column(
                children: [
                  InterestButton(
                    interested: activity.iAmInterested,
                    count: activity.interestCount,
                    onPressed: onToggleInterest,
                  ),
                  if (activity.owner case final owner?)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: UserAvatar(user: owner, radius: 12),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _date(DateTime date) => DateFormat.MMMd().format(date);
}

/// "Sat 3 Oct, 19:00" for a timed occurrence (device-local time), "Sat 3
/// Oct" for an all-day one.
String nextOccurrenceLabel(OccurrenceRef next) {
  if (next.startsAt case final start?) {
    return DateFormat('EEE d MMM, HH:mm').format(start.toLocal());
  }
  if (next.startDate case final date?) {
    return DateFormat('EEE d MMM').format(date);
  }
  return 'Scheduled';
}

class _Detail extends StatelessWidget {
  const new({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }
}

/// An activity's status as a small chip.
class StatusChip extends StatelessWidget {
  const new({required this.status, this.dense = false, super.key});

  final ActivityStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground) = switch (status) {
      ActivityStatus.idea => (colors.surfaceContainerHighest, colors.onSurface),
      ActivityStatus.planning => (
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
      ),
      ActivityStatus.scheduled => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      ActivityStatus.done => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      ActivityStatus.dropped || ActivityStatus.$unknown => (
        colors.surfaceContainer,
        colors.onSurfaceVariant,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 6 : 10,
          vertical: dense ? 2 : 4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(status.icon, size: dense ? 14 : 16, color: foreground),
            const SizedBox(width: 4),
            Text(
              status.label,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}

/// A custom-field value shown on the card, e.g. "⭐ 8.1".
class CardAttributeChip extends StatelessWidget {
  const new({required this.attribute, super.key});

  final CardAttribute attribute;

  @override
  Widget build(BuildContext context) {
    final value = FieldValues.display(attribute.type, attribute.value);
    return Tooltip(
      message: attribute.label,
      child: Chip(
        label: Text(value),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// "Vote": I haven't answered one of the activity's open polls.
class VoteBadge extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'An open poll is waiting for your vote',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Text(
            'Vote',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: colors.onError),
          ),
        ),
      ),
    );
  }
}

/// The interest heart with its count.
class InterestButton extends StatelessWidget {
  const new({
    required this.interested,
    required this.count,
    required this.onPressed,
    super.key,
  });

  final bool interested;
  final int count;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      toggled: interested,
      label: interested ? "I'm interested" : 'Mark as interested',
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                interested ? Icons.favorite : Icons.favorite_border,
                color: interested ? colors.error : colors.onSurfaceVariant,
                size: 22,
              ),
              const SizedBox(width: 2),
              Text('$count'),
            ],
          ),
        ),
      ),
    );
  }
}
