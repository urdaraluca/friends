// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/poll.dart';
import '../models/poll_create.dart';
import '../models/poll_option_create.dart';
import '../models/poll_update.dart';
import '../models/vote_request.dart';

part 'polls_client.g.dart';

@RestApi()
abstract class PollsClient {
  factory PollsClient(Dio dio, {String? baseUrl}) = _PollsClient;

  /// List Polls.
  ///
  /// Oldest first.
  @GET('/api/v1/activities/{activity_id}/polls')
  Future<List<Poll>> listPolls({
    @Path('activity_id') required String activityId,
  });

  /// Create Poll.
  ///
  /// Any member; at most 10 polls per activity. ``closes_at`` must be in the future.
  @POST('/api/v1/activities/{activity_id}/polls')
  Future<Poll> createPoll({
    @Path('activity_id') required String activityId,
    @Body() required PollCreate body,
  });

  /// Get Poll
  @GET('/api/v1/polls/{poll_id}')
  Future<Poll> getPoll({
    @Path('poll_id') required String pollId,
  });

  /// Update Poll.
  ///
  /// The poll's manager (its creator, the activity's owner or an admin). ``closes_at`` must be.
  /// in the future, or the stored value sent back unchanged.
  @PUT('/api/v1/polls/{poll_id}')
  Future<Poll> updatePoll({
    @Path('poll_id') required String pollId,
    @Body() required PollUpdate body,
  });

  /// Delete Poll.
  ///
  /// The poll's manager.
  @DELETE('/api/v1/polls/{poll_id}')
  Future<void> deletePoll({
    @Path('poll_id') required String pollId,
  });

  /// Close Poll.
  ///
  /// The poll's manager. Closing a closed poll changes nothing.
  @POST('/api/v1/polls/{poll_id}/close')
  Future<Poll> closePoll({
    @Path('poll_id') required String pollId,
  });

  /// Reopen Poll.
  ///
  /// The poll's manager. Also clears a ``closes_at`` that has passed.
  @POST('/api/v1/polls/{poll_id}/reopen')
  Future<Poll> reopenPoll({
    @Path('poll_id') required String pollId,
  });

  /// Add Poll Option.
  ///
  /// Any member, while the poll is open; the option goes last.
  @POST('/api/v1/polls/{poll_id}/options')
  Future<Poll> addPollOption({
    @Path('poll_id') required String pollId,
    @Body() required PollOptionCreate body,
  });

  /// Delete Poll Option.
  ///
  /// Whoever added the option (while it has no votes) or the poll's manager. Its votes are.
  /// removed; a poll keeps at least 2 options.
  @DELETE('/api/v1/polls/{poll_id}/options/{option_id}')
  Future<Poll> deletePollOption({
    @Path('poll_id') required String pollId,
    @Path('option_id') required String optionId,
  });

  /// Set My Vote.
  ///
  /// Replaces the caller's whole vote; an empty list retracts it and duplicate IDs are.
  /// ignored. At most one option on a single-choice poll.
  @PUT('/api/v1/polls/{poll_id}/votes/me')
  Future<Poll> setMyVote({
    @Path('poll_id') required String pollId,
    @Body() required VoteRequest body,
  });
}
