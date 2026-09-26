import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/router/routes.dart';
import 'package:intl/intl.dart';

/// A piece of a feed sentence; names and titles are bold.
typedef FeedSpan = ({String text, bool bold});

FeedSpan _plain(String text) => (text: text, bold: false);
FeedSpan _bold(String text) => (text: text, bold: true);

String? _data(FeedItem item, String key) {
  final data = item.data;
  if (data is! Map) return null;
  final value = data[key];
  return value is String ? value : value?.toString();
}

const _statusLabels = {
  'idea': 'Ideas',
  'planning': 'Planning',
  'scheduled': 'Scheduled',
  'done': 'Done',
  'dropped': 'Dropped',
};

/// The sentence for [item]: "**Ana** added **Picnic**".
List<FeedSpan> feedSentence(FeedItem item) {
  final actor = _bold(item.actor?.displayName ?? 'Someone');
  final title = item.subjectTitle;
  final subject = _bold(title ?? 'something');
  final quoted = _bold('“${title ?? '…'}”');
  return switch (item.action) {
    'group.created' => [actor, _plain(' created the group')],
    'group.updated' => [actor, _plain(' updated the group')],
    'group.ownership_transferred' => [
      actor,
      _plain(' made '),
      subject,
      _plain(' the owner'),
    ],
    'member.joined' => [subject, _plain(' joined the group')],
    'member.left' => [subject, _plain(' left the group')],
    'member.removed' => [actor, _plain(' removed '), subject],
    'member.role_changed' => [
      actor,
      _plain(' made '),
      subject,
      _plain(_data(item, 'to') == 'admin' ? ' an admin' : ' a member'),
    ],
    'activity.created' => [actor, _plain(' added '), subject],
    'activity.updated' => [actor, _plain(' edited '), subject],
    'activity.status_changed' => switch (_data(item, 'to')) {
      'done' => [actor, _plain(' marked '), subject, _plain(' as done')],
      final to => [
        actor,
        _plain(' moved '),
        subject,
        _plain(' to ${_statusLabels[to] ?? to}'),
      ],
    },
    'activity.deleted' => [actor, _plain(' deleted '), subject],
    'activity.interest_added' => [actor, _plain(' is interested in '), subject],
    'event.created' => [actor, _plain(' planned '), subject],
    'event.updated' => [actor, _plain(' changed '), subject],
    'event.deleted' => [actor, _plain(' called off '), subject],
    'event.occurrence_cancelled' => [actor, _plain(' cancelled one '), subject],
    'event.occurrence_restored' => [
      actor,
      _plain(' brought back one '),
      subject,
    ],
    'poll.created' => [actor, _plain(' asked '), quoted],
    'poll.updated' => [actor, _plain(' edited the poll '), quoted],
    'poll.closed' => [actor, _plain(' closed the poll '), quoted],
    'poll.reopened' => [actor, _plain(' reopened the poll '), quoted],
    'poll.deleted' => [actor, _plain(' deleted the poll '), quoted],
    'poll.option_added' => [
      actor,
      _plain(' added '),
      _bold(_data(item, 'label') ?? 'an option'),
      _plain(' to '),
      quoted,
    ],
    'poll.voted' => [actor, _plain(' voted in '), quoted],
    'wheel.spun' => [actor, _plain(' spun the wheel: '), subject],
    'wheel.accepted' => [actor, _plain(" said let's do "), subject],
    _ => [actor, _plain(' did something')],
  };
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
    'member' || 'group' => Routes.groupHub(groupId),
    _ => null,
  };
}

/// "just now", "5 min ago", "3 h ago", "yesterday", else the date.
String feedTime(DateTime at, DateTime now) {
  final local = at.toLocal();
  final elapsed = now.difference(local);
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes} min ago';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  if (day == today) return '${elapsed.inHours} h ago';
  if (day == DateTime(today.year, today.month, today.day - 1)) {
    return 'yesterday, ${DateFormat.Hm().format(local)}';
  }
  return local.year == now.year
      ? DateFormat('EEE d MMM').format(local)
      : DateFormat('d MMM y').format(local);
}
