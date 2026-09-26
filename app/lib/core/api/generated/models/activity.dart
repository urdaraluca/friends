// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'activity_status.dart';
import 'card_attribute.dart';
import 'event_ref.dart';
import 'link.dart';
import 'occurrence_ref.dart';
import 'user_public.dart';

part 'activity.freezed.dart';
part 'activity.g.dart';

@Freezed()
abstract class Activity with _$Activity {
  const factory Activity({
    required String id,
    @JsonKey(name: 'group_id')
    required String groupId,
    required String title,
    required ActivityStatus status,
    @JsonKey(name: 'category_id')
    required String? categoryId,
    required UserPublic? owner,
    @JsonKey(name: 'due_date')
    required DateTime? dueDate,
    @JsonKey(name: 'estimated_cost')
    required int? estimatedCost,
    required String? currency,
    @JsonKey(name: 'cost_per_person')
    required bool costPerPerson,
    @JsonKey(name: 'interest_count')
    required int interestCount,
    @JsonKey(name: 'i_am_interested')
    required bool iAmInterested,
    @JsonKey(name: 'poll_count')
    required int pollCount,
    @JsonKey(name: 'open_poll_count')
    required int openPollCount,
    @JsonKey(name: 'my_unvoted_poll_count')
    required int myUnvotedPollCount,
    @JsonKey(name: 'card_attributes')
    required List<CardAttribute> cardAttributes,
    @JsonKey(name: 'next_occurrence')
    required OccurrenceRef? nextOccurrence,
    @JsonKey(name: 'can_edit')
    required bool canEdit,
    @JsonKey(name: 'can_delete')
    required bool canDelete,
    @JsonKey(name: 'created_at')
    required DateTime createdAt,
    @JsonKey(name: 'updated_at')
    required DateTime updatedAt,
    required String? description,
    required String? notes,
    @JsonKey(name: 'location_name')
    required String? locationName,
    required String? address,
    required List<Link> links,
    required dynamic attributes,
    @JsonKey(name: 'interested_users')
    required List<UserPublic> interestedUsers,
    @JsonKey(name: 'created_by')
    required UserPublic? createdBy,
    @JsonKey(name: 'status_changed_at')
    required DateTime statusChangedAt,
    @JsonKey(name: 'completed_at')
    required DateTime? completedAt,
    required int version,
    required List<EventRef> events,
  }) = _Activity;
  
  factory Activity.fromJson(Map<String, Object?> json) => _$ActivityFromJson(json);
}
