// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

/// What the group is for (contract section 17.1).
///
/// It picks the categories a new group gets, and the app's tabs (a book club has Books).
@JsonEnum()
enum GroupKind {
  @JsonValue('general')
  general('general'),
  @JsonValue('movie_night')
  movieNight('movie_night'),
  @JsonValue('book_club')
  bookClub('book_club'),
  /// Default value for all unparsed values, allows backward compatibility when adding new values on the backend.
  $unknown(null);

  const GroupKind(this.json);

  factory GroupKind.fromJson(String json) => values.firstWhere(
        (e) => e.json == json,
        orElse: () => $unknown,
      );

  final String? json;
  String toJson() {
    final value = json;
    if (value == null) {
      throw StateError('Cannot convert enum value with null JSON representation to String. '
          'This usually happens for \$unknown or @JsonValue(null) entries.');
    }
    return value as String;
  }

  @override
  String toString() => json?.toString() ?? super.toString();
  /// Returns all defined enum values excluding the $unknown value.
  static List<GroupKind> get $valuesDefined => values.where((value) => value != $unknown).toList();
}
