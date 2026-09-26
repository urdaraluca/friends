import 'package:friends/core/api/date_only.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/features/recap/domain/recap_period.dart';
import 'package:intl/intl.dart';

/// A line under a card's headline, with an optional category colour dot.
class RecapLine {
  const new(this.text, {this.color});

  final String text;

  /// `#RRGGBB`, or null for no dot.
  final String? color;
}

/// One card of a recap story: one stat, big.
class RecapCard {
  const new({
    required this.eyebrow,
    required this.headline,
    this.number,
    this.subtitle,
    this.lines = const [],
    this.color,
    this.activityId,
  });

  /// A small label above the headline ("Memories made").
  final String eyebrow;

  /// The big text: a name, a title, or [number] as text.
  final String headline;

  /// When the headline is a count: it counts up to it.
  final int? number;
  final String? subtitle;
  final List<RecapLine> lines;

  /// The card's background (`#RRGGBB`), or null for the story's palette.
  final String? color;

  /// An activity the card is about, opened by its button.
  final String? activityId;
}

String _plural(int count, String one, [String? many]) =>
    count == 1 ? '1 $one' : '$count ${many ?? '${one}s'}';

/// The cards of [recap]'s story, in order. Cards without data are left out;
/// a period with nothing in it gets a single "quiet" card after the intro.
List<RecapCard> recapStory(Recap recap, {required String groupName}) {
  final start = DateOnly.from(recap.start);
  final label = periodLabel(recap.period, DateTime(start.year, start.month));
  final unit = recap.period == RecapPeriod.year ? 'year' : 'month';
  final intro = RecapCard(
    eyebrow: 'Recap',
    headline: 'Your $label',
    subtitle: 'with $groupName',
    lines: [
      if (!recap.complete) RecapLine("So far: this $unit isn't over yet."),
    ],
  );

  final quiet =
      recap.memoryCount == 0 &&
      recap.ideasAdded == 0 &&
      recap.eventsPlanned == 0 &&
      recap.pollsCreated == 0 &&
      recap.wheelDecisions == 0;
  if (quiet) {
    return [
      intro,
      RecapCard(
        eyebrow: 'Nothing yet',
        headline: 'A quiet $unit',
        subtitle:
            'Add ideas and mark them done: they will fill your next recap.',
      ),
    ];
  }

  const shown = 6;
  final memories = recap.memories;
  final planners = recap.planners;
  final categories = recap.topCategories;
  final poll = recap.topPoll;
  final wait = recap.longestWait;
  final month = recap.busiestMonth;
  final wanted = recap.mostWanted;
  return [
    intro,
    RecapCard(
      eyebrow: 'Memories made',
      headline: '${recap.memoryCount}',
      number: recap.memoryCount,
      subtitle: switch (recap.memoryCount) {
        0 => 'Nothing marked done yet.',
        1 => 'thing you did together',
        _ => 'things you did together',
      },
      lines: [
        for (final memory in memories.take(shown))
          RecapLine(memory.title, color: memory.color),
        if (recap.memoryCount > shown)
          RecapLine('…and ${recap.memoryCount - shown} more'),
      ],
    ),
    if (planners.isNotEmpty)
      RecapCard(
        eyebrow: 'Most active planner',
        headline: planners.first.user.displayName,
        subtitle: [
          _plural(planners.first.score, 'plan'),
          if (planners.first.ideas > 0) _plural(planners.first.ideas, 'idea'),
          if (planners.first.events > 0)
            _plural(planners.first.events, 'event'),
          if (planners.first.polls > 0) _plural(planners.first.polls, 'poll'),
          if (planners.first.done > 0) '${planners.first.done} done',
        ].join(' · '),
        lines: [
          for (final (index, planner) in planners.skip(1).indexed)
            RecapLine(
              '${index + 2}. ${planner.user.displayName} · '
              '${_plural(planner.score, 'plan')}',
            ),
        ],
      ),
    if (categories.isNotEmpty)
      RecapCard(
        eyebrow: 'Top category',
        headline: categories.first.name,
        subtitle: _plural(categories.first.count, 'memory', 'memories'),
        color: categories.first.color,
        lines: [
          for (final category in categories.skip(1))
            RecapLine(
              '${category.name} · ${category.count}',
              color: category.color,
            ),
        ],
      ),
    if (recap.wheelDecisions > 0)
      RecapCard(
        eyebrow: 'The wheel decided',
        headline: '${recap.wheelDecisions}',
        number: recap.wheelDecisions,
        subtitle: recap.wheelDecisions == 1
            ? 'time you let fate choose'
            : 'times you let fate choose',
      ),
    if (poll != null)
      RecapCard(
        eyebrow: 'Most-voted poll',
        headline: poll.question,
        subtitle: '${_plural(poll.voters, 'voter')} · ${poll.activityTitle}',
        activityId: poll.activityId,
      ),
    if (wait != null && wait.days > 0)
      RecapCard(
        eyebrow: 'Worth the wait',
        headline: '${wait.days}',
        number: wait.days,
        subtitle: wait.days == 1
            ? 'day from idea to memory'
            : 'days from idea to memory',
        lines: [RecapLine(wait.activity.title, color: wait.activity.color)],
        activityId: wait.activity.id,
      ),
    if (month != null && recap.period == RecapPeriod.year)
      RecapCard(
        eyebrow: 'Busiest month',
        headline: DateFormat.MMMM().format(DateOnly.from(month.month)),
        subtitle: _plural(month.count, 'memory', 'memories'),
      ),
    if (wanted != null)
      RecapCard(
        eyebrow: 'Still on the wish list',
        headline: wanted.title,
        subtitle:
            '${_plural(wanted.interested, 'person', 'people')} '
            'interested',
        color: wanted.color,
        activityId: wanted.activityId,
      ),
    RecapCard(
      eyebrow: 'In numbers',
      headline: recap.complete ? "That's a wrap" : 'So far',
      lines: [
        RecapLine('${_plural(recap.ideasAdded, 'idea')} added'),
        RecapLine('${_plural(recap.eventsPlanned, 'event')} planned'),
        RecapLine('${_plural(recap.pollsCreated, 'poll')} created'),
        if (recap.newMembers > 0)
          RecapLine(
            recap.newMembers == 1
                ? '1 new member'
                : '${recap.newMembers} new members',
          ),
      ],
    ),
  ];
}
