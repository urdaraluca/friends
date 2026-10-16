// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

/// A book's genre (contract section 17.2). The app translates the names.
@JsonEnum()
enum BookGenre {
  @JsonValue('fiction')
  fiction('fiction'),
  @JsonValue('fantasy')
  fantasy('fantasy'),
  @JsonValue('sci_fi')
  sciFi('sci_fi'),
  @JsonValue('mystery_thriller')
  mysteryThriller('mystery_thriller'),
  @JsonValue('romance')
  romance('romance'),
  @JsonValue('horror')
  horror('horror'),
  @JsonValue('classics')
  classics('classics'),
  @JsonValue('history')
  history('history'),
  @JsonValue('biography')
  biography('biography'),
  @JsonValue('non_fiction')
  nonFiction('non_fiction'),
  @JsonValue('self_help')
  selfHelp('self_help'),
  @JsonValue('poetry')
  poetry('poetry'),
  @JsonValue('children')
  children('children'),
  @JsonValue('young_adult')
  youngAdult('young_adult'),
  @JsonValue('comics')
  comics('comics'),
  @JsonValue('other')
  other('other'),
  /// Default value for all unparsed values, allows backward compatibility when adding new values on the backend.
  $unknown(null);

  const BookGenre(this.json);

  factory BookGenre.fromJson(String json) => values.firstWhere(
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
  static List<BookGenre> get $valuesDefined => values.where((value) => value != $unknown).toList();
}
