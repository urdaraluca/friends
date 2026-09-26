/// JSON bodies as the API sends them (contract section 9).
library;

import 'dart:convert';

Map<String, Object?> meJson({
  String id = '0190c3a5-0000-7000-8000-000000000001',
  String email = 'ana@example.com',
  String displayName = 'Ana',
  Map<String, Object?>? birthday,
  String timezone = 'Europe/Bucharest',
  String? locale,
  String? avatarUrl,
}) => {
  'id': id,
  'email': email,
  'display_name': displayName,
  'avatar_url': avatarUrl,
  'birthday': birthday,
  'timezone': timezone,
  'locale': locale,
  'created_at': '2026-09-01T10:00:00Z',
};

Map<String, Object?> tokenPairJson({
  String access = 'access-1',
  String refresh = 'refresh-1',
  int expiresIn = 900,
}) => {
  'access_token': access,
  'refresh_token': refresh,
  'token_type': 'bearer',
  'access_expires_in': expiresIn,
  'refresh_expires_at': '2026-10-25T10:00:00Z',
};

Map<String, Object?> authSessionJson({
  Map<String, Object?>? user,
  Map<String, Object?>? tokens,
  Map<String, Object?>? joinedGroup,
}) => {
  'user': user ?? meJson(),
  'tokens': tokens ?? tokenPairJson(),
  'joined_group': joinedGroup,
};

Map<String, Object?> groupSummaryJson({
  String id = '0190c3a5-0000-7000-8000-0000000000aa',
  String name = 'Movie night',
}) => {
  'id': id,
  'name': name,
  'emoji': null,
  'color': null,
  'member_count': 2,
  'my_role': 'member',
  'created_at': '2026-09-01T10:00:00Z',
};

/// API paths used across tests.
abstract final class ApiPaths {
  static const login = '/api/v1/auth/login';
  static const register = '/api/v1/auth/register';
  static const refresh = '/api/v1/auth/refresh';
  static const logout = '/api/v1/auth/logout';
  static const logoutAll = '/api/v1/auth/logout-all';
  static const me = '/api/v1/me';
  static const password = '/api/v1/me/password';
  static const deletion = '/api/v1/me/deletion';
  static const groups = '/api/v1/groups';
  static const health = '/api/v1/health';
}

/// An access token shaped like the API's JWTs (contract section 4.1) for
/// user [sub]; [nonce] tells tokens of the same user apart. Unsigned: the
/// app never verifies tokens, it only reads `sub`.
String fakeJwt({required String sub, String nonce = ''}) {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return [
    part({'alg': 'HS256', 'typ': 'JWT'}),
    part({'sub': sub, 'typ': 'access', 'n': nonce}),
    'signature',
  ].join('.');
}
