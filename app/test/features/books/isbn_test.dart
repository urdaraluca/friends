import 'package:flutter_test/flutter_test.dart';
import 'package:friends/features/books/domain/book_languages.dart';
import 'package:friends/features/books/domain/isbn.dart';

/// The same cases as the server's `tests/unit/test_isbn.py`.
void main() {
  test('normalizeIsbn', () {
    const cases = {
      '9780441172719': '9780441172719',
      '978-0-441-17271-9': '9780441172719',
      '0441172717': '9780441172719',
      '0 441 17271 7': '9780441172719',
      '080442957X': '9780804429573',
      '080442957x': '9780804429573',
      '9791032305690': '9791032305690',
      '9780441172718': null,
      '0441172718': null,
      '9770441172719': null,
      '97804411727': null,
      'abcdefghij': null,
      '': null,
    };
    for (final MapEntry(key: value, value: expected) in cases.entries) {
      expect(normalizeIsbn(value), expected, reason: value);
    }
  });

  test('language names are their own, and unknown codes are shown', () {
    expect(bookLanguageName('ro'), 'Română');
    expect(bookLanguageName('de'), 'Deutsch');
    expect(bookLanguageName('eo'), 'EO');
  });
}
