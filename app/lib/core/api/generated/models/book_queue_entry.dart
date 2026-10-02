// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'user_public.dart';

part 'book_queue_entry.freezed.dart';
part 'book_queue_entry.g.dart';

@Freezed()
abstract class BookQueueEntry with _$BookQueueEntry {
  const factory BookQueueEntry({
    required UserPublic user,
    @JsonKey(name: 'joined_at')
    required DateTime joinedAt,
  }) = _BookQueueEntry;
  
  factory BookQueueEntry.fromJson(Map<String, Object?> json) => _$BookQueueEntryFromJson(json);
}
