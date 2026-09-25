// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'transfer_ownership.freezed.dart';
part 'transfer_ownership.g.dart';

@Freezed()
abstract class TransferOwnership with _$TransferOwnership {
  const factory TransferOwnership({
    @JsonKey(name: 'user_id')
    required String userId,
  }) = _TransferOwnership;
  
  factory TransferOwnership.fromJson(Map<String, Object?> json) => _$TransferOwnershipFromJson(json);
}
