// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'vote_request.freezed.dart';
part 'vote_request.g.dart';

@Freezed()
abstract class VoteRequest with _$VoteRequest {
  const factory VoteRequest({
    @JsonKey(name: 'option_ids')
    required List<String> optionIds,
  }) = _VoteRequest;
  
  factory VoteRequest.fromJson(Map<String, Object?> json) => _$VoteRequestFromJson(json);
}
