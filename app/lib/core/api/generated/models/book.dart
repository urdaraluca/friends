// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'book_genre.dart';
import 'book_queue_entry.dart';
import 'user_public.dart';

part 'book.freezed.dart';
part 'book.g.dart';

@Freezed()
abstract class Book with _$Book {
  const factory Book({
    required String id,
    @JsonKey(name: 'group_id')
    required String groupId,
    required String title,
    required String? author,
    required String? description,
    required String? isbn,
    required BookGenre? genre,
    required String? language,
    @JsonKey(name: 'cover_updated_at')
    required DateTime? coverUpdatedAt,
    required UserPublic? owner,
    required UserPublic? holder,
    @JsonKey(name: 'held_since')
    required DateTime? heldSince,
    required List<BookQueueEntry> queue,
    @JsonKey(name: 'in_my_queue')
    required bool inMyQueue,
    @JsonKey(name: 'rating_average')
    required num? ratingAverage,
    @JsonKey(name: 'rating_count')
    required int ratingCount,
    @JsonKey(name: 'my_rating')
    required int? myRating,
    @JsonKey(name: 'can_edit')
    required bool canEdit,
    @JsonKey(name: 'can_hand_over')
    required bool canHandOver,
    @JsonKey(name: 'created_at')
    required DateTime createdAt,
    @JsonKey(name: 'updated_at')
    required DateTime updatedAt,
  }) = _Book;
  
  factory Book.fromJson(Map<String, Object?> json) => _$BookFromJson(json);
}
