import 'dart:typed_data';

import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/date_only.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:material_ui/material_ui.dart' show Rect;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'recap_providers.g.dart';

/// The device clock, for the recap banner. Tests override it.
@Riverpod(keepAlive: true)
DateTime Function() recapClock(Ref ref) => DateTime.now;

/// A group's recap (`GET /groups/{id}/recap`) for the [period] starting on
/// [start] (`YYYY-MM-DD`), or the current one (in the group's timezone)
/// when null.
@riverpod
Future<Recap> groupRecap(
  Ref ref,
  String groupId,
  RecapPeriod period,
  String? start,
) {
  ref.watch(currentUserIdProvider);
  final client = ref.watch(recapClientProvider);
  return apiCall(
    () => client.getGroupRecap(
      groupId: groupId,
      period: period,
      start: start == null ? null : DateOnly.parse(start),
    ),
  );
}

/// The key of a recap banner, remembered once dismissed.
String recapBannerKey(String groupId, RecapPeriod period, DateTime start) =>
    '$groupId|${period.json}|${DateOnly.format(start)}';

/// Remembers the dismissed recap banners on this device.
class RecapBannerStore {
  new([SharedPreferencesAsync? prefs]) : _prefs = prefs;

  static const _key = 'friends.recap_banners_dismissed';

  /// The most keys kept: older ones are for periods long gone.
  static const _max = 50;

  SharedPreferencesAsync? _prefs;

  SharedPreferencesAsync get _store => _prefs ??= SharedPreferencesAsync();

  /// The dismissed keys, oldest first (storage failures read as none).
  Future<List<String>> read() async {
    try {
      return await _store.getStringList(_key) ?? const [];
    } on Object {
      return const [];
    }
  }

  Future<void> write(List<String> keys) async {
    try {
      await _store.setStringList(
        _key,
        keys.length > _max ? keys.sublist(keys.length - _max) : keys,
      );
    } on Object {
      // Best effort.
    }
  }
}

@Riverpod(keepAlive: true)
RecapBannerStore recapBannerStore(Ref ref) => RecapBannerStore();

/// The recap banners dismissed on this device ([recapBannerKey]s).
@Riverpod(keepAlive: true)
class DismissedRecapBanners extends _$DismissedRecapBanners {
  @override
  Future<List<String>> build() => ref.read(recapBannerStoreProvider).read();

  Future<void> dismiss(String key) async {
    final keys = [...?state.value, key];
    state = AsyncData(keys);
    await ref.read(recapBannerStoreProvider).write(keys);
  }
}

/// Shares a recap card as an image (`share_plus`).
class RecapSharer {
  const new();

  Future<void> shareImage(
    Uint8List png, {
    required String text,
    Rect? origin,
  }) => SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(png, mimeType: 'image/png', name: 'friends-recap.png'),
      ],
      text: text,
      sharePositionOrigin: origin,
    ),
  );
}

/// The app's [RecapSharer]. Tests override it to record what is shared.
@Riverpod(keepAlive: true)
RecapSharer recapSharer(Ref ref) => const RecapSharer();
