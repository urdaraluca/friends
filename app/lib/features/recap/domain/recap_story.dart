import 'package:friends/core/api/date_only.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/features/recap/domain/recap_period.dart';
import 'package:friends/l10n/l10n.dart';
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

/// The cards of [recap]'s story, in order. Cards without data are left out;
/// a period with nothing in it gets a single "quiet" card after the intro.
List<RecapCard> recapStory(Recap recap, {required String groupName}) {
  final start = DateOnly.from(recap.start);
  final l10n = currentL10n;
  final label = periodLabel(recap.period, DateTime(start.year, start.month));
  final year = recap.period == RecapPeriod.year;
  final intro = RecapCard(
    eyebrow: l10n.recap,
    headline: toBeginningOfSentenceCase(l10n.recapYour(label)),
    subtitle: l10n.recapWith(groupName),
    lines: [
      if (!recap.complete)
        RecapLine(year ? l10n.recapSoFarYear : l10n.recapSoFarMonth),
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
        eyebrow: l10n.nothingYet,
        headline: year ? l10n.quietYear : l10n.quietMonth,
        subtitle: l10n.quietHelp,
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
      eyebrow: l10n.memoriesMade,
      headline: '${recap.memoryCount}',
      number: recap.memoryCount,
      subtitle: switch (recap.memoryCount) {
        0 => l10n.nothingDoneYet,
        final count => l10n.thingsTogether(count),
      },
      lines: [
        for (final memory in memories.take(shown))
          RecapLine(memory.title, color: memory.color),
        if (recap.memoryCount > shown)
          RecapLine(l10n.andMore(recap.memoryCount - shown)),
      ],
    ),
    if (planners.isNotEmpty)
      RecapCard(
        eyebrow: l10n.mostActivePlanner,
        headline: planners.first.user.displayName,
        subtitle: [
          l10n.planCount(planners.first.score),
          if (planners.first.ideas > 0) l10n.ideaCount(planners.first.ideas),
          if (planners.first.events > 0) l10n.eventCount(planners.first.events),
          if (planners.first.polls > 0) l10n.pollCount(planners.first.polls),
          if (planners.first.done > 0) l10n.doneCount(planners.first.done),
        ].join(' · '),
        lines: [
          for (final (index, planner) in planners.skip(1).indexed)
            RecapLine(
              '${index + 2}. ${planner.user.displayName} · '
              '${l10n.planCount(planner.score)}',
            ),
        ],
      ),
    if (categories.isNotEmpty)
      RecapCard(
        eyebrow: l10n.topCategory,
        headline: categories.first.name,
        subtitle: l10n.memoryCount(categories.first.count),
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
        eyebrow: l10n.wheelDecided,
        headline: '${recap.wheelDecisions}',
        number: recap.wheelDecisions,
        subtitle: l10n.timesFate(recap.wheelDecisions),
      ),
    if (poll != null)
      RecapCard(
        eyebrow: l10n.mostVotedPoll,
        headline: poll.question,
        subtitle: '${l10n.voterCount(poll.voters)} · ${poll.activityTitle}',
        activityId: poll.activityId,
      ),
    if (wait != null && wait.days > 0)
      RecapCard(
        eyebrow: l10n.worthTheWait,
        headline: '${wait.days}',
        number: wait.days,
        subtitle: l10n.daysIdeaToMemory(wait.days),
        lines: [RecapLine(wait.activity.title, color: wait.activity.color)],
        activityId: wait.activity.id,
      ),
    if (month != null && recap.period == RecapPeriod.year)
      RecapCard(
        eyebrow: l10n.busiestMonth,
        headline: toBeginningOfSentenceCase(
          DateFormat.MMMM().format(DateOnly.from(month.month)),
        ),
        subtitle: l10n.memoryCount(month.count),
      ),
    if (wanted != null)
      RecapCard(
        eyebrow: l10n.stillWishList,
        headline: wanted.title,
        subtitle: l10n.peopleInterested(wanted.interested),
        color: wanted.color,
        activityId: wanted.activityId,
      ),
    RecapCard(
      eyebrow: l10n.inNumbers,
      headline: recap.complete ? l10n.thatsAWrap : l10n.soFar,
      lines: [
        RecapLine(l10n.ideasAdded(recap.ideasAdded)),
        RecapLine(l10n.eventsPlanned(recap.eventsPlanned)),
        RecapLine(l10n.pollsCreated(recap.pollsCreated)),
        if (recap.newMembers > 0) RecapLine(l10n.newMembers(recap.newMembers)),
      ],
    ),
  ];
}
