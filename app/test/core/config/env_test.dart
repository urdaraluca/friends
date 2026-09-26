import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/config/env.dart';

void main() {
  group('Env.webBaseUrl', () {
    for (final (base, expected) in [
      ('https://friends.example.com/', 'https://friends.example.com'),
      ('https://example.com/friends/', 'https://example.com/friends'),
      (
        'https://example.com/a/friends/index.html',
        'https://example.com/a/friends',
      ),
      ('https://example.com/friends/?x=1#/join', 'https://example.com/friends'),
      ('http://localhost:5000/', 'http://localhost:5000'),
    ]) {
      test('$base -> $expected', () {
        expect(Env.webBaseUrl(Uri.parse(base)), expected);
      });
    }
  });
}
