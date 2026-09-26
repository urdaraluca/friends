// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'recap_activity.dart';
import 'recap_category.dart';
import 'recap_idea.dart';
import 'recap_month.dart';
import 'recap_period.dart';
import 'recap_planner.dart';
import 'recap_poll.dart';
import 'recap_wait.dart';

part 'recap.freezed.dart';
part 'recap.g.dart';

@Freezed()
abstract class Recap with _$Recap {
  const factory Recap({
    required RecapPeriod period,
    required DateTime start,
    required DateTime end,
    required String timezone,
    required bool complete,
    @JsonKey(name: 'memory_count')
    required int memoryCount,
    required List<RecapActivity> memories,
    required List<RecapPlanner> planners,
    @JsonKey(name: 'top_categories')
    required List<RecapCategory> topCategories,
    @JsonKey(name: 'ideas_added')
    required int ideasAdded,
    @JsonKey(name: 'events_planned')
    required int eventsPlanned,
    @JsonKey(name: 'polls_created')
    required int pollsCreated,
    @JsonKey(name: 'wheel_decisions')
    required int wheelDecisions,
    @JsonKey(name: 'new_members')
    required int newMembers,
    @JsonKey(name: 'top_poll')
    required RecapPoll? topPoll,
    @JsonKey(name: 'longest_wait')
    required RecapWait? longestWait,
    @JsonKey(name: 'busiest_month')
    required RecapMonth? busiestMonth,
    @JsonKey(name: 'most_wanted')
    required RecapIdea? mostWanted,
  }) = _Recap;
  
  factory Recap.fromJson(Map<String, Object?> json) => _$RecapFromJson(json);
}
