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

/// IDs used across the group fixtures. [anaId] is `meJson()`'s user.
abstract final class Ids {
  static const anaId = '0190c3a5-0000-7000-8000-000000000001';
  static const beaId = '0190c3a5-0000-7000-8000-000000000002';
  static const crisId = '0190c3a5-0000-7000-8000-000000000003';
  static const groupId = '0190c3a5-0000-7000-8000-0000000000aa';
  static const otherGroupId = '0190c3a5-0000-7000-8000-0000000000bb';
  static const inviteId = '0190c3a5-0000-7000-8000-0000000000c1';
}

Map<String, Object?> groupSummaryJson({
  String id = Ids.groupId,
  String name = 'Movie night',
  String? emoji,
  String? color,
  int memberCount = 2,
  String myRole = 'member',
}) => {
  'id': id,
  'name': name,
  'emoji': emoji,
  'color': color,
  'member_count': memberCount,
  'my_role': myRole,
  'created_at': '2026-09-01T10:00:00Z',
};

Map<String, Object?> groupJson({
  String id = Ids.groupId,
  String name = 'Movie night',
  String? emoji = '🎬',
  String? color = '#1E88E5',
  int memberCount = 2,
  String myRole = 'member',
  String? description,
  String currency = 'EUR',
  String timezone = 'Europe/Bucharest',
  bool membersCanInvite = true,
}) => {
  ...groupSummaryJson(
    id: id,
    name: name,
    emoji: emoji,
    color: color,
    memberCount: memberCount,
    myRole: myRole,
  ),
  'description': description,
  'currency': currency,
  'timezone': timezone,
  'members_can_invite': membersCanInvite,
  'created_by': userPublicJson(),
  'updated_at': '2026-09-01T10:00:00Z',
};

Map<String, Object?> userPublicJson({
  String id = Ids.anaId,
  String displayName = 'Ana',
}) => {'id': id, 'display_name': displayName, 'avatar_url': null};

Map<String, Object?> memberJson({
  String userId = Ids.anaId,
  String displayName = 'Ana',
  String role = 'member',
  Map<String, Object?>? birthday,
  bool? showBirthday,
}) => {
  'user': userPublicJson(id: userId, displayName: displayName),
  'role': role,
  'joined_at': '2026-09-01T10:00:00Z',
  'birthday': birthday,
  'show_birthday': showBirthday,
};

Map<String, Object?> inviteJson({
  String id = Ids.inviteId,
  String groupId = Ids.groupId,
  String code = 'ABCDEFGHJK',
  String status = 'valid',
  String? expiresAt = '2026-10-08T10:00:00Z',
  int? maxUses,
  int useCount = 0,
  bool canDelete = true,
  String createdById = Ids.anaId,
  String createdByName = 'Ana',
}) => {
  'id': id,
  'group_id': groupId,
  'code': code,
  'url': 'https://friends.example.com/join/$code',
  'status': status,
  'expires_at': expiresAt,
  'max_uses': maxUses,
  'use_count': useCount,
  'revoked_at': status == 'revoked' ? '2026-10-02T10:00:00Z' : null,
  'created_by': userPublicJson(id: createdById, displayName: createdByName),
  'created_at': '2026-10-01T10:00:00Z',
  'can_delete': canDelete,
};

Map<String, Object?> invitePreviewJson({
  String code = 'ABCDEFGHJK',
  String status = 'valid',
  String groupName = 'Movie night',
  int memberCount = 3,
  String? invitedByName = 'Bea',
  String? expiresAt = '2026-10-08T10:00:00Z',
}) => {
  'code': code,
  'status': status,
  'group': {
    'name': groupName,
    'emoji': '🎬',
    'color': '#1E88E5',
    'member_count': memberCount,
  },
  'invited_by_name': invitedByName,
  'expires_at': expiresAt,
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

  static String group(String id) => '$groups/$id';
  static String members(String groupId) => '${group(groupId)}/members';
  static String member(String groupId, String userId) =>
      '${members(groupId)}/$userId';
  static String role(String groupId, String userId) =>
      '${member(groupId, userId)}/role';
  static String mySettings(String groupId) => '${members(groupId)}/me/settings';
  static String transfer(String groupId) =>
      '${group(groupId)}/transfer-ownership';
  static String invites(String groupId) => '${group(groupId)}/invites';
  static String invite(String groupId, String inviteId) =>
      '${invites(groupId)}/$inviteId';
  static String invitePreview(String code) => '/api/v1/invites/$code';
  static String acceptInvite(String code) => '${invitePreview(code)}/accept';
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
