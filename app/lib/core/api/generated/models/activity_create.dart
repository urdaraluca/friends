// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'activity_status.dart';
import 'link.dart';

part 'activity_create.freezed.dart';
part 'activity_create.g.dart';

/// ``owner_id: null`` means the creator.
@Freezed()
abstract class ActivityCreate with _$ActivityCreate {
  const factory ActivityCreate({
    required String title,
    @JsonKey(name: 'cost_per_person')
    @Default(true)
    bool costPerPerson,
    @Default(ActivityStatus.idea)
    ActivityStatus status,
    String? description,
    String? notes,
    @JsonKey(name: 'category_id')
    String? categoryId,
    @JsonKey(name: 'owner_id')
    String? ownerId,
    @JsonKey(name: 'due_date')
    DateTime? dueDate,
    @JsonKey(name: 'estimated_cost')
    int? estimatedCost,
    String? currency,
    @JsonKey(name: 'location_name')
    String? locationName,
    String? address,
    List<Link>? links,
    dynamic attributes,
  }) = _ActivityCreate;
  
  factory ActivityCreate.fromJson(Map<String, Object?> json) => _$ActivityCreateFromJson(json);
}
