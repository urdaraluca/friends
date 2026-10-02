import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/backlog/domain/activity_rules.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:intl/intl.dart';

/// A piece of a feed sentence; names and titles are bold.
typedef FeedSpan = ({String text, bool bold});

// Around a bold value inside a translated sentence; private-use characters,
// so no name or title contains them.
const _boldStart = '\u{E000}';
const _boldEnd = '\u{E001}';

String _bold(String text) => '$_boldStart$text$_boldEnd';

/// [sentence] cut into spans: the parts marked by [_bold] bold, the rest
/// plain. Each language orders the parts its own way.
List<FeedSpan> _spans(String sentence) => [
  for (final (index, part) in sentence.split(_boldStart).indexed)
    if (index == 0)
      (text: part, bold: false)
    else ...[
      (text: part.split(_boldEnd).first, bold: true),
      (text: part.split(_boldEnd).skip(1).join(), bold: false),
    ],
].where((span) => span.text.isNotEmpty).toList();

String? _data(FeedItem item, String key) {
  final data = item.data;
  if (data is! Map) return null;
  final value = data[key];
  return value is String ? value : value?.toString();
}

/// The column a status change moved an idea to, e.g. "Planning".
String _statusLabel(String to) => switch (ActivityStatus.fromJson(to)) {
  ActivityStatus.idea => currentL10n.feedStatusIdeas,
  ActivityStatus.$unknown => to,
  final status => status.label,
};

/// The sentence for [item]: "**Ana** added **Picnic**", in the app's
/// language.
List<FeedSpan> feedSentence(FeedItem item) {
  final l10n = currentL10n;
  final actor = _bold(item.actor?.displayName ?? l10n.someone);
  final title = item.subjectTitle;
  final subject = _bold(title ?? l10n.something);
  final poll = _bold(l10n.quoted(title ?? '…'));
  return _spans(switch (item.action) {
    'group.created' => l10n.feedGroupCreated(actor),
    'group.updated' => l10n.feedGroupUpdated(actor),
    'group.ownership_transferred' => l10n.feedOwnershipTransferred(
      actor,
      subject,
    ),
    'member.joined' => l10n.feedMemberJoined(subject),
    'member.left' => l10n.feedMemberLeft(subject),
    'member.removed' => l10n.feedMemberRemoved(actor, subject),
    'member.role_changed' =>
      _data(item, 'to') == 'admin'
          ? l10n.feedMadeAdmin(actor, subject)
          : l10n.feedMadeMember(actor, subject),
    'activity.created' => l10n.feedActivityCreated(actor, subject),
    'activity.updated' => l10n.feedActivityUpdated(actor, subject),
    'activity.status_changed' => switch (_data(item, 'to')) {
      'done' => l10n.feedActivityDone(actor, subject),
      final to => l10n.feedActivityMoved(
        actor,
        subject,
        to == null ? '' : _statusLabel(to),
      ),
    },
    'activity.deleted' => l10n.feedActivityDeleted(actor, subject),
    'activity.interest_added' => l10n.feedInterestAdded(actor, subject),
    'event.created' => l10n.feedEventCreated(actor, subject),
    'event.updated' => l10n.feedEventUpdated(actor, subject),
    'event.deleted' => l10n.feedEventDeleted(actor, subject),
    'event.occurrence_cancelled' => l10n.feedOccurrenceCancelled(
      actor,
      subject,
    ),
    'event.occurrence_edited' => l10n.feedOccurrenceEdited(actor, subject),
    'event.occurrence_restored' => l10n.feedOccurrenceRestored(actor, subject),
    'poll.created' => l10n.feedPollCreated(actor, poll),
    'poll.updated' => l10n.feedPollUpdated(actor, poll),
    'poll.closed' => l10n.feedPollClosed(actor, poll),
    'poll.reopened' => l10n.feedPollReopened(actor, poll),
    'poll.deleted' => l10n.feedPollDeleted(actor, poll),
    'poll.option_added' => l10n.feedOptionAdded(
      actor,
      _bold(_data(item, 'label') ?? l10n.anOption),
      poll,
    ),
    'poll.voted' => l10n.feedPollVoted(actor, poll),
    'wheel.spun' => l10n.feedWheelSpun(actor, subject),
    'wheel.accepted' => l10n.feedWheelAccepted(actor, subject),
    'book.added' => l10n.feedBookAdded(actor, subject),
    'book.lent' => l10n.feedBookLent(
      actor,
      subject,
      _bold(_data(item, 'to_name') ?? l10n.someone),
    ),
    'book.returned' => l10n.feedBookReturned(actor, subject),
    _ => l10n.feedSomething(actor),
  });
}

/// The screen [item] opens, or null.
String? feedTarget(String groupId, FeedItem item) {
  final id = item.subjectId;
  if (!item.subjectExists || id == null) return null;
  return switch (item.subjectType) {
    'activity' => Routes.activity(groupId, id),
    'event' => Routes.event(groupId, id),
    'poll' => switch (_data(item, 'activity_id')) {
      final activityId? => Routes.activity(groupId, activityId),
      null => null,
    },
    'spin' => Routes.wheelHistory(groupId),
    'book' => Routes.book(groupId, id),
    'member' || 'group' => Routes.groupHub(groupId),
    _ => null,
  };
}

/// "just now", "5 min ago", "3 h ago", "yesterday", else the date.
String feedTime(DateTime at, DateTime now) {
  final l10n = currentL10n;
  final local = at.toLocal();
  final elapsed = now.difference(local);
  if (elapsed.inMinutes < 1) return l10n.justNow;
  if (elapsed.inHours < 1) return l10n.minutesAgo(elapsed.inMinutes);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  if (day == today) return l10n.hoursAgo(elapsed.inHours);
  if (day == DateTime(today.year, today.month, today.day - 1)) {
    return l10n.yesterdayAt(DateFormat.Hm().format(local));
  }
  return local.year == now.year
      ? DateFormat('EEE d MMM').format(local)
      : DateFormat('d MMM y').format(local);
}
