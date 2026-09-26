import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/auth/access_token.dart';

import '../../helpers/api_fixtures.dart';

void main() {
  group('AccessToken.subject', () {
    test('reads sub from a JWT', () {
      expect(AccessToken.subject(fakeJwt(sub: 'user-1')), 'user-1');
      // Base64url without padding, as the backend's PyJWT encodes it.
      expect(
        AccessToken.subject(
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
          'eyJzdWIiOiIwMTkwYzNhNS0wMDAwLTcwMDAtODAwMC0wMDAwMDAwMDAwMDEiLCJz'
          'aWQiOiJmIiwidHYiOjAsInR5cCI6ImFjY2VzcyJ9.'
          'x',
        ),
        '0190c3a5-0000-7000-8000-000000000001',
      );
    });

    test('is null for anything that is not a readable JWT', () {
      expect(AccessToken.subject(null), isNull);
      expect(AccessToken.subject('access-1'), isNull);
      expect(AccessToken.subject('a.%%%.c'), isNull);
      expect(AccessToken.subject('a.bm90IGpzb24.c'), isNull); // "not json"
      expect(AccessToken.subject('a.WzFd.c'), isNull); // [1]
      expect(AccessToken.subject('a.eyJzdWIiOjF9.c'), isNull); // {"sub":1}
    });
  });
}
