import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/features/backlog/data/backlog_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'polls_providers.g.dart';

/// An activity's polls, oldest first (`GET /activities/{id}/polls`).
///
/// Mutations put the server's response in place ([put], [remove]), so a
/// vote or a new option shows at once without reloading every poll.
@riverpod
class Polls extends _$Polls {
  @override
  Future<List<Poll>> build(String activityId) {
    ref.watch(currentUserIdProvider);
    final client = ref.watch(pollsClientProvider);
    return apiCall(() => client.listPolls(activityId: activityId));
  }

  /// Replaces the poll with [poll]'s ID, or appends [poll].
  void put(Poll poll) {
    final polls = state.value;
    if (polls == null) return;
    final known = polls.any((p) => p.id == poll.id);
    state = AsyncData([
      for (final p in polls)
        if (p.id == poll.id) poll else p,
      if (!known) poll,
    ]);
  }

  /// Drops the poll with [pollId].
  void remove(String pollId) {
    final polls = state.value;
    if (polls == null) return;
    state = AsyncData([
      for (final p in polls)
        if (p.id != pollId) p,
    ]);
  }
}

/// Every poll mutation (contract section 8.9). Each method throws
/// `ApiException`s; on success it puts the server's poll into
/// [pollsProvider] and refreshes the activity and the backlog, whose poll
/// counters ("Vote" badge) changed.
@Riverpod(keepAlive: true)
class PollsController extends _$PollsController {
  @override
  void build() {}

  PollsClient get _client => ref.read(pollsClientProvider);

  Future<Poll> _apply(String activityId, Future<Poll> Function() call) async {
    final poll = await apiCall(call);
    ref.read(pollsProvider(activityId).notifier).put(poll);
    _countersChanged(activityId);
    return poll;
  }

  void _countersChanged(String activityId) => ref
      .read(backlogControllerProvider.notifier)
      .activitiesChanged(activityId: activityId);

  /// `POST /activities/{id}/polls`. Any member; at most 10 per activity.
  Future<Poll> create(String activityId, PollCreate body) => _apply(
    activityId,
    () => _client.createPoll(activityId: activityId, body: body),
  );

  /// `PUT /polls/{id}`: the question and closing time (managers).
  Future<Poll> update(Poll poll, PollUpdate body) => _apply(
    poll.activityId,
    () => _client.updatePoll(pollId: poll.id, body: body),
  );

  /// `DELETE /polls/{id}` (managers).
  Future<void> delete(Poll poll) async {
    await apiCall(() => _client.deletePoll(pollId: poll.id));
    ref.read(pollsProvider(poll.activityId).notifier).remove(poll.id);
    _countersChanged(poll.activityId);
  }

  /// `POST /polls/{id}/close` (managers; idempotent).
  Future<Poll> close(Poll poll) =>
      _apply(poll.activityId, () => _client.closePoll(pollId: poll.id));

  /// `POST /polls/{id}/reopen` (managers). A passed closing time is cleared.
  Future<Poll> reopen(Poll poll) =>
      _apply(poll.activityId, () => _client.reopenPoll(pollId: poll.id));

  /// `POST /polls/{id}/options`: any member while the poll is open.
  Future<Poll> addOption(Poll poll, PollOptionCreate body) => _apply(
    poll.activityId,
    () => _client.addPollOption(pollId: poll.id, body: body),
  );

  /// `DELETE /polls/{id}/options/{optionId}` (`can_delete`).
  Future<Poll> deleteOption(Poll poll, String optionId) => _apply(
    poll.activityId,
    () => _client.deletePollOption(pollId: poll.id, optionId: optionId),
  );

  /// `PUT /polls/{id}/votes/me`: replaces my whole vote; empty retracts.
  Future<Poll> vote(Poll poll, List<String> optionIds) => _apply(
    poll.activityId,
    () => _client.setMyVote(
      pollId: poll.id,
      body: VoteRequest(optionIds: optionIds),
    ),
  );

  /// Reloads the activity's polls (e.g. after `409 poll_closed`).
  void refresh(String activityId) => ref.invalidate(pollsProvider(activityId));
}
