// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'link.dart';

part 'activity_update.freezed.dart';
part 'activity_update.g.dart';

/// The complete new state. ``owner_id: null`` means unowned.
@Freezed()
abstract class ActivityUpdate with _$ActivityUpdate {
  const factory ActivityUpdate({
    required String title,
    required int version,
    @JsonKey(name: 'cost_per_person')
    @Default(true)
    bool costPerPerson,
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
  }) = _ActivityUpdate;
  
  factory ActivityUpdate.fromJson(Map<String, Object?> json) => _$ActivityUpdateFromJson(json);
}
