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
  static const movieCategoryId = '0190c3a5-0000-7000-8000-0000000000d1';
  static const gamesCategoryId = '0190c3a5-0000-7000-8000-0000000000d2';
  static const activityId = '0190c3a5-0000-7000-8000-0000000000e1';
  static const otherActivityId = '0190c3a5-0000-7000-8000-0000000000e2';
  static const pollId = '0190c3a5-0000-7000-8000-0000000000f1';
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
  static String categories(String groupId) => '${group(groupId)}/categories';
  static String category(String id) => '/api/v1/categories/$id';
  static String activities(String groupId) => '${group(groupId)}/activities';
  static String activity(String id) => '/api/v1/activities/$id';
  static String activityStatus(String id) => '${activity(id)}/status';
  static String interest(String id) => '${activity(id)}/interest';
  static String polls(String activityId) => '${activity(activityId)}/polls';
  static String poll(String id) => '/api/v1/polls/$id';
  static String myVote(String pollId) => '${poll(pollId)}/votes/me';
  static String pollOptions(String pollId) => '${poll(pollId)}/options';
  static String wheelCandidates(String groupId) =>
      '${group(groupId)}/wheel/candidates';
  static String spins(String groupId) => '${group(groupId)}/wheel/spins';
  static String acceptSpin(String spinId) =>
      '/api/v1/wheel/spins/$spinId/accept';
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

/// The seeded "Movie night" field definitions (contract section 6.5).
List<Map<String, Object?>> movieFieldDefsJson() => [
  {
    'key': 'genre',
    'label': 'Genre',
    'type': 'select',
    'options': ['Action', 'Comedy', 'Drama'],
    'min': null,
    'max': null,
    'show_on_card': false,
  },
  {
    'key': 'imdb_rating',
    'label': 'IMDb rating',
    'type': 'rating',
    'options': null,
    'min': 0,
    'max': 10,
    'show_on_card': true,
  },
  {
    'key': 'imdb_url',
    'label': 'IMDb link',
    'type': 'url',
    'options': null,
    'min': null,
    'max': null,
    'show_on_card': false,
  },
  {
    'key': 'year',
    'label': 'Year',
    'type': 'year',
    'options': null,
    'min': null,
    'max': null,
    'show_on_card': false,
  },
  {
    'key': 'runtime_min',
    'label': 'Runtime (min)',
    'type': 'number',
    'options': null,
    'min': 1,
    'max': 600,
    'show_on_card': false,
  },
];

Map<String, Object?> categoryJson({
  String id = Ids.movieCategoryId,
  String groupId = Ids.groupId,
  String? parentId,
  String name = 'Movie night',
  String? color = '#7E57C2',
  String? effectiveColor,
  String? icon = 'movie',
  int position = 0,
  List<Map<String, Object?>>? fieldDefs,
  List<Map<String, Object?>>? effectiveFieldDefs,
  bool canEdit = true,
}) {
  final own = fieldDefs ?? const [];
  return {
    'id': id,
    'group_id': groupId,
    'parent_id': parentId,
    'name': name,
    'color': color,
    'effective_color': effectiveColor ?? color,
    'icon': icon,
    'position': position,
    'field_defs': own,
    'effective_field_defs': effectiveFieldDefs ?? own,
    'created_by': userPublicJson(),
    'can_edit': canEdit,
    'can_delete': canEdit,
    'created_at': '2026-09-01T10:00:00Z',
    'updated_at': '2026-09-01T10:00:00Z',
  };
}

Map<String, Object?> categoryNodeJson({
  List<Map<String, Object?>> subcategories = const [],
  String id = Ids.movieCategoryId,
  String name = 'Movie night',
  String? color = '#7E57C2',
  String? icon = 'movie',
  List<Map<String, Object?>>? fieldDefs,
  bool canEdit = true,
}) => {
  ...categoryJson(
    id: id,
    name: name,
    color: color,
    icon: icon,
    fieldDefs: fieldDefs,
    canEdit: canEdit,
  ),
  'subcategories': subcategories,
};

/// The default "Movie night" category with its fields, and "Games".
List<Map<String, Object?>> categoryTreeJson() => [
  categoryNodeJson(fieldDefs: movieFieldDefsJson()),
  categoryNodeJson(
    id: Ids.gamesCategoryId,
    name: 'Games',
    color: '#1565C0',
    icon: 'games',
  ),
];

Map<String, Object?> activitySummaryJson({
  String id = Ids.activityId,
  String groupId = Ids.groupId,
  String title = 'Dune',
  String status = 'idea',
  String? categoryId = Ids.movieCategoryId,
  Map<String, Object?>? owner,
  String? dueDate,
  int? estimatedCost,
  String? currency,
  bool costPerPerson = true,
  int interestCount = 1,
  bool iAmInterested = true,
  int myUnvotedPollCount = 0,
  List<Map<String, Object?>> cardAttributes = const [],
  Map<String, Object?>? nextOccurrence,
  bool canDelete = true,
}) => {
  'id': id,
  'group_id': groupId,
  'title': title,
  'status': status,
  'category_id': categoryId,
  'owner': owner,
  'due_date': dueDate,
  'estimated_cost': estimatedCost,
  'currency': currency ?? (estimatedCost == null ? null : 'EUR'),
  'cost_per_person': costPerPerson,
  'interest_count': interestCount,
  'i_am_interested': iAmInterested,
  'poll_count': myUnvotedPollCount,
  'open_poll_count': myUnvotedPollCount,
  'my_unvoted_poll_count': myUnvotedPollCount,
  'card_attributes': cardAttributes,
  'next_occurrence': nextOccurrence,
  'can_edit': true,
  'can_delete': canDelete,
  'created_at': '2026-09-20T10:00:00Z',
  'updated_at': '2026-09-20T10:00:00Z',
};

Map<String, Object?> activityJson({
  String id = Ids.activityId,
  String title = 'Dune',
  String status = 'idea',
  String? categoryId = Ids.movieCategoryId,
  Map<String, Object?>? owner,
  Map<String, Object?> attributes = const {},
  List<Map<String, Object?>> links = const [],
  List<Map<String, Object?>> interestedUsers = const [],
  int version = 1,
  bool canDelete = true,
  String? description,
  int? estimatedCost,
}) => {
  ...activitySummaryJson(
    id: id,
    title: title,
    status: status,
    categoryId: categoryId,
    owner: owner,
    canDelete: canDelete,
    estimatedCost: estimatedCost,
    interestCount: interestedUsers.length,
    iAmInterested: interestedUsers.any((u) => u['id'] == Ids.anaId),
  ),
  'description': description,
  'notes': null,
  'location_name': null,
  'address': null,
  'links': links,
  'attributes': attributes,
  'interested_users': interestedUsers,
  'created_by': userPublicJson(),
  'status_changed_at': '2026-09-20T10:00:00Z',
  'completed_at': null,
  'version': version,
  'events': <Object?>[],
};

Map<String, Object?> activityPageJson(
  List<Map<String, Object?>> items, {
  String? nextCursor,
}) => {'items': items, 'next_cursor': nextCursor};

Map<String, Object?> pollOptionJson({
  required String id,
  required String label,
  int position = 0,
  String? url,
  List<Map<String, Object?>> voters = const [],
  bool canDelete = false,
}) => {
  'id': id,
  'label': label,
  'url': url,
  'position': position,
  'vote_count': voters.length,
  'voters': voters,
  'added_by': userPublicJson(),
  'can_delete': canDelete,
};

Map<String, Object?> pollJson({
  String id = Ids.pollId,
  String activityId = Ids.activityId,
  String question = 'Which movie?',
  bool allowMultiple = false,
  bool isOpen = true,
  String? closesAt,
  String? closedAt,
  List<Map<String, Object?>>? options,
  List<String> myOptionIds = const [],
  List<String> winningOptionIds = const [],
  bool canManage = true,
}) {
  final all =
      options ??
      [
        pollOptionJson(id: 'o1', label: 'Dune'),
        pollOptionJson(id: 'o2', label: 'Up', position: 1),
      ];
  final voters = {
    for (final option in all)
      for (final voter in option['voters']! as List<Object?>)
        (voter! as Map<String, Object?>)['id'],
  };
  return {
    'id': id,
    'group_id': Ids.groupId,
    'activity_id': activityId,
    'question': question,
    'allow_multiple': allowMultiple,
    'closes_at': closesAt,
    'closed_at': closedAt,
    'is_open': isOpen,
    'options': all,
    'my_option_ids': myOptionIds,
    'total_voters': voters.length,
    'winning_option_ids': winningOptionIds,
    'created_by': userPublicJson(),
    'can_manage': canManage,
    'created_at': '2026-09-20T10:00:00Z',
    'updated_at': '2026-09-20T10:00:00Z',
  };
}

Map<String, Object?> wheelCandidatesJson(
  List<Map<String, Object?>> items, {
  int? total,
}) => {'items': items, 'total': total ?? items.length};

Map<String, Object?> wheelSpinJson({
  String id = 'spin-1',
  List<Map<String, Object?>>? candidates,
  int resultIndex = 1,
  String? resultActivityId,
  String? acceptedAt,
  Map<String, Object?>? acceptedBy,
}) {
  final slices =
      candidates ??
      [
        {
          'id': Ids.activityId,
          'title': 'Dune',
          'category_id': Ids.movieCategoryId,
          'color': '#7E57C2',
        },
        {
          'id': Ids.otherActivityId,
          'title': 'Catan',
          'category_id': Ids.gamesCategoryId,
          'color': '#1565C0',
        },
      ];
  return {
    'id': id,
    'group_id': Ids.groupId,
    'spun_by': userPublicJson(),
    'filters': {
      'status': ['idea', 'planning'],
      'category_id': null,
      'include_subcategories': true,
      'interested_by': Ids.anaId,
      'owner_id': null,
      'cost_max': null,
      'include_unpriced': true,
      'due_before': null,
    },
    'candidates': slices,
    'result_index': resultIndex,
    'result': slices[resultIndex],
    'result_activity_id': resultActivityId ?? slices[resultIndex]['id'],
    'accepted_at': acceptedAt,
    'accepted_by': acceptedBy,
    'created_at': '2026-09-26T18:00:00Z',
  };
}
