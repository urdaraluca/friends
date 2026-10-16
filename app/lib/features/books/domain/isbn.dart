/// ISBNs, checked the way the server checks them (contract section 17.5).
library;

final _separators = RegExp(r'[\s-]');

/// The ISBN-13 for an ISBN-10 or ISBN-13 (spaces and hyphens allowed), or
/// null when [value] isn't one (wrong length, characters or check digit).
String? normalizeIsbn(String value) {
  final raw = value.replaceAll(_separators, '').toUpperCase();
  if (raw.length == 10 && RegExp(r'^\d{9}[\dX]$').hasMatch(raw)) {
    var sum = 0;
    for (var i = 0; i < 10; i++) {
      final digit = raw[i] == 'X' ? 10 : int.parse(raw[i]);
      sum += (10 - i) * digit;
    }
    if (sum % 11 != 0) return null;
    final core = '978${raw.substring(0, 9)}';
    return '$core${_isbn13CheckDigit(core)}';
  }
  if (raw.length == 13 &&
      RegExp(r'^97[89]\d{10}$').hasMatch(raw) &&
      _isbn13CheckDigit(raw.substring(0, 12)) == raw[12]) {
    return raw;
  }
  return null;
}

String _isbn13CheckDigit(String firstTwelve) {
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(firstTwelve[i]) * (i.isOdd ? 3 : 1);
  }
  return '${(10 - sum % 10) % 10}';
}
