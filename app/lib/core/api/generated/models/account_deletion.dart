// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'account_deletion.freezed.dart';
part 'account_deletion.g.dart';

@Freezed()
abstract class AccountDeletion with _$AccountDeletion {
  const factory AccountDeletion({
    required String password,
  }) = _AccountDeletion;
  
  factory AccountDeletion.fromJson(Map<String, Object?> json) => _$AccountDeletionFromJson(json);
}
