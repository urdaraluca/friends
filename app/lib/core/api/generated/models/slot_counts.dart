// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'availability_slot.dart';
import 'user_public.dart';

part 'slot_counts.freezed.dart';
part 'slot_counts.g.dart';

/// How the group's current members answered for one slot of a day.
@Freezed()
abstract class SlotCounts with _$SlotCounts {
  const factory SlotCounts({
    required AvailabilitySlot slot,
    required int free,
    required int maybe,
    required int busy,
    required int unknown,
    @JsonKey(name: 'free_users')
    required List<UserPublic> freeUsers,
    @JsonKey(name: 'maybe_users')
    required List<UserPublic> maybeUsers,
  }) = _SlotCounts;
  
  factory SlotCounts.fromJson(Map<String, Object?> json) => _$SlotCountsFromJson(json);
}
