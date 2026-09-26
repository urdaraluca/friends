import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/token_holder.dart';
import 'package:friends/core/auth/token_store.dart';
import 'package:friends/core/device/device_info.dart';
import 'package:friends/core/network/dio_provider.dart';
import 'package:friends/features/groups/data/last_group_store.dart';
import 'package:friends/features/invites/data/invite_sharer.dart';
import 'package:friends/features/recap/data/recap_providers.dart';
import 'package:material_ui/material_ui.dart' show Rect;

import 'api_fixtures.dart';
import 'fake_http_adapter.dart';

/// A [TokenStore] in memory.
class InMemoryTokenStore implements TokenStore {
  new([this.refreshToken]);

  String? refreshToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> writeRefreshToken(String refreshToken) async =>
      this.refreshToken = refreshToken;

  @override
  Future<void> clear() async => refreshToken = null;
}

/// A [LastGroupStore] in memory.
class InMemoryLastGroupStore implements LastGroupStore {
  new([this.groupId]);

  String? groupId;

  @override
  Future<String?> read() async => groupId;

  @override
  Future<void> write(String groupId) async => this.groupId = groupId;

  @override
  Future<void> forget(String groupId) async {
    if (this.groupId == groupId) this.groupId = null;
  }
}

/// An [InviteSharer] that records what would have been shared.
class FakeInviteSharer extends InviteSharer {
  final List<String> shared = [];

  @override
  Future<void> share(
    Invite invite, {
    required String groupName,
    Rect? origin,
  }) async => shared.add(InviteSharer.message(invite, groupName));
}

/// A [RecapSharer] that records the images it would have shared.
class FakeRecapSharer extends RecapSharer {
  final List<({Uint8List png, String text})> shared = [];

  @override
  Future<void> shareImage(
    Uint8List png, {
    required String text,
    Rect? origin,
  }) async => shared.add((png: png, text: text));
}

/// A clock tests move by hand.
class FakeClock {
  new([DateTime? now]) : now = now ?? DateTime.utc(2026, 10);

  DateTime now;

  DateTime call() => now;

  void advance(Duration duration) => now = now.add(duration);
}

/// The app's real network and auth stack (Dio, interceptors, refresher,
/// generated clients, `AuthController`) wired to a [FakeHttpClientAdapter],
/// an [InMemoryTokenStore] and a [FakeClock].
///
/// ```dart
/// final backend = TestBackend(storedRefreshToken: 'refresh-0')
///   ..stubRestore();
/// final container = backend.container();
/// ```
///
/// Pass a [store] to share it between two backends: two browser tabs share
/// one refresh token (local storage) but each has its own access token.
class TestBackend {
  new({String? storedRefreshToken, InMemoryTokenStore? store})
    : store = store ?? InMemoryTokenStore(storedRefreshToken);

  final adapter = FakeHttpClientAdapter();
  final InMemoryTokenStore store;
  final clock = FakeClock();
  late final holder = TokenHolder(clock: clock.call);

  /// The last opened group (`/` goes back to it).
  final lastGroup = InMemoryLastGroupStore();

  /// What the share buttons shared.
  final sharer = FakeInviteSharer();

  /// The recap images shared.
  final recapSharer = FakeRecapSharer();

  /// The device date the recap banner sees: mid-month, so no banner unless
  /// a test moves it.
  DateTime today = DateTime(2026, 10, 15);

  /// Overrides for a `ProviderScope` or `ProviderContainer`.
  List<Override> get overrides => [
    apiBaseUrlProvider.overrideWithValue('http://api.test'),
    httpClientAdapterProvider.overrideWithValue(adapter),
    tokenStoreProvider.overrideWithValue(store),
    tokenHolderProvider.overrideWithValue(holder),
    deviceLabelProvider.overrideWithValue('web'),
    deviceTimezoneProvider.overrideWith((ref) async => 'Europe/Bucharest'),
    lastGroupStoreProvider.overrideWithValue(lastGroup),
    inviteSharerProvider.overrideWithValue(sharer),
    recapClockProvider.overrideWithValue(() => today),
    recapSharerProvider.overrideWithValue(recapSharer),
  ];

  /// A container disposed at the end of the test.
  ProviderContainer container() => ProviderContainer.test(overrides: overrides);

  /// `POST /auth/refresh` answers with a new pair, `GET /me` with [me], and
  /// `GET /groups` with no groups.
  void stubRestore({Map<String, Object?>? me}) {
    adapter
      ..onJson('POST', ApiPaths.refresh, tokenPairJson())
      ..onJson('GET', ApiPaths.me, me ?? meJson())
      ..onJson('GET', ApiPaths.groups, <Object?>[]);
  }

  /// `GET /groups` answers with [groups] (`groupSummaryJson`s).
  void stubGroups(List<Map<String, Object?>> groups) =>
      adapter.onJson('GET', ApiPaths.groups, groups);

  /// A group I'm in: `GET /groups` (also listing it), `GET /groups/{id}`,
  /// its members and its invites.
  void stubGroup({
    Map<String, Object?>? group,
    List<Map<String, Object?>>? members,
    List<Map<String, Object?>> invites = const [],
  }) {
    final details = group ?? groupJson();
    final id = details['id']! as String;
    final summary = {
      for (final key in groupSummaryJson().keys) key: details[key],
    };
    adapter
      ..onJson('GET', ApiPaths.groups, [summary])
      ..onJson('GET', ApiPaths.group(id), details)
      ..onJson(
        'GET',
        ApiPaths.members(id),
        members ??
            [
              memberJson(role: details['my_role']! as String),
              memberJson(userId: Ids.beaId, displayName: 'Bea'),
            ],
      )
      ..onJson('GET', ApiPaths.invites(id), invites);
    stubBacklog(groupId: id, categories: const []);
  }

  /// The group's categories (`categoryNodeJson`s, default: Movie night and
  /// Games) and one page of activities (`activitySummaryJson`s).
  void stubBacklog({
    String groupId = Ids.groupId,
    List<Map<String, Object?>>? categories,
    List<Map<String, Object?>> activities = const [],
    String? nextCursor,
  }) {
    adapter
      ..onJson(
        'GET',
        ApiPaths.categories(groupId),
        categories ?? categoryTreeJson(),
      )
      ..onJson(
        'GET',
        ApiPaths.activities(groupId),
        activityPageJson(activities, nextCursor: nextCursor),
      );
  }

  /// Number of `POST /auth/refresh` calls so far.
  int get refreshCount => adapter.requestsTo('POST', ApiPaths.refresh).length;
}
