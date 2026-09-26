import 'package:friends/core/api/generated/export.dart';

/// Custom-field values (`activities.attributes`, contract section 6.3): how
/// the form turns text into JSON values, checks them before sending (the
/// server stays the authority), and how values are shown.
abstract final class FieldValues {
  static const maxText = 200;
  static const maxLongText = 5000;
  static const maxUrl = 2048;
  static const minYear = 1800;
  static const maxYear = 2200;

  /// A rating's range when its definition leaves it open.
  static const defaultRatingMin = 0;
  static const defaultRatingMax = 10;

  /// The lowest allowed value of [def], if any.
  static num? minOf(FieldDef def) => switch (def.type) {
    FieldType.rating => def.min ?? defaultRatingMin,
    FieldType.year => minYear,
    _ => def.min,
  };

  /// The highest allowed value of [def], if any.
  static num? maxOf(FieldDef def) => switch (def.type) {
    FieldType.rating => def.max ?? defaultRatingMax,
    FieldType.year => maxYear,
    _ => def.max,
  };

  /// The JSON value for [text] typed into [def]'s input: null clears the
  /// key (an empty input), numbers become `num`s, years `int`s, the rest
  /// strings. Returns the trimmed text when it can't be parsed, so the
  /// server reports it; `validate` catches that first.
  static Object? parse(FieldDef def, String text) {
    final value = text.trim();
    if (value.isEmpty) return null;
    return switch (def.type) {
      FieldType.number => _number(value) ?? value,
      FieldType.rating => _number(value) ?? value,
      FieldType.year => int.tryParse(value) ?? value,
      _ => value,
    };
  }

  /// A client-side check of [text] for [def], or null when it looks valid.
  static String? validate(FieldDef def, String? text) {
    final value = (text ?? '').trim();
    if (value.isEmpty) return null;
    switch (def.type) {
      case FieldType.text:
        return value.runes.length > maxText
            ? 'At most $maxText characters'
            : null;
      case FieldType.longText:
        return value.runes.length > maxLongText
            ? 'At most $maxLongText characters'
            : null;
      case FieldType.url:
        return isWebUrl(value) ? null : 'Enter a full http(s) link';
      case FieldType.select:
        return (def.options ?? const []).contains(value)
            ? null
            : 'Pick one of the options';
      case FieldType.year:
        final year = int.tryParse(value);
        if (year == null) return 'Enter a year';
        return year < minYear || year > maxYear
            ? 'Between $minYear and $maxYear'
            : null;
      case FieldType.number || FieldType.rating:
        final number = _number(value);
        if (number == null) return 'Enter a number';
        final min = minOf(def);
        final max = maxOf(def);
        if ((min != null && number < min) || (max != null && number > max)) {
          return _rangeMessage(min, max);
        }
        if (def.type == FieldType.rating &&
            (number * 10).roundToDouble() != number * 10) {
          return 'At most one decimal';
        }
        return null;
      case FieldType.$unknown:
        return null;
    }
  }

  /// The text a field's input starts with, from a stored [value].
  static String toText(Object? value) => switch (value) {
    null => '',
    final num number => _formatNumber(number),
    _ => value.toString(),
  };

  /// [value] of a [type] field as shown on cards and in the detail view.
  static String display(FieldType type, Object? value) => switch (type) {
    FieldType.rating => '⭐ ${toText(value)}',
    _ => toText(value),
  };

  /// Whether [text] is an absolute http or https URL with a host.
  static bool isWebUrl(String text) {
    final uri = Uri.tryParse(text);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty &&
        text.length <= maxUrl;
  }

  /// A field key derived from [label]: lowercase ASCII letters, digits and
  /// underscores, starting with a letter, at most 30 characters
  /// (`^[a-z][a-z0-9_]{0,29}$`, contract section 6.1). Empty when [label]
  /// has no usable characters.
  static String keyFromLabel(String label) {
    var key = _stripAccents(label.toLowerCase())
        .replaceAll(RegExp('[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (key.isEmpty) return '';
    if (!RegExp('^[a-z]').hasMatch(key)) key = 'f_$key';
    if (key.length > 30) {
      key = key.substring(0, 30).replaceAll(RegExp(r'_+$'), '');
    }
    return key;
  }

  /// Whether [key] is a valid field key.
  static bool isValidKey(String key) =>
      RegExp(r'^[a-z][a-z0-9_]{0,29}$').hasMatch(key);

  static num? _number(String value) {
    final number = num.tryParse(value.replaceAll(',', '.'));
    return number != null && number.isFinite ? number : null;
  }

  static String _formatNumber(num number) {
    if (number is int) return '$number';
    if (number == number.roundToDouble()) return number.toInt().toString();
    return number.toString();
  }

  static String _rangeMessage(num? min, num? max) {
    if (min != null && max != null) {
      return 'Between ${_formatNumber(min)} and ${_formatNumber(max)}';
    }
    if (min != null) return 'At least ${_formatNumber(min)}';
    return 'At most ${_formatNumber(max!)}';
  }

  static const _accents = {
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'å': 'a',
    'ă': 'a',
    'ç': 'c',
    'č': 'c',
    'ć': 'c',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ñ': 'n',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ș': 's',
    'ş': 's',
    'š': 's',
    'ț': 't',
    'ţ': 't',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ý': 'y',
    'ÿ': 'y',
    'ž': 'z',
    'ß': 'ss',
  };

  static String _stripAccents(String text) =>
      text.split('').map((c) => _accents[c] ?? c).join();
}

/// Human names of the field types, for the field editor.
extension FieldTypeLabel on FieldType {
  String get label => switch (this) {
    FieldType.text => 'Text',
    FieldType.longText => 'Long text',
    FieldType.number => 'Number',
    FieldType.rating => 'Rating',
    FieldType.url => 'Link',
    FieldType.select => 'Choice',
    FieldType.year => 'Year',
    FieldType.$unknown => 'Other',
  };
}
