import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'last_group_store.g.dart';

/// Remembers the last group opened on this device, so `/` can go straight
/// back to it.
abstract interface class LastGroupStore {
  /// The last opened group's ID, or null.
  Future<String?> read();

  /// Remembers [groupId] as the last opened group.
  Future<void> write(String groupId);

  /// Forgets [groupId] if it is the one remembered (after leaving or
  /// deleting it).
  Future<void> forget(String groupId);
}

/// [LastGroupStore] on `SharedPreferencesAsync`.
///
/// Best effort: a storage failure (or a platform without the plugin, as in
/// widget tests) reads as "no last group" and drops writes.
class SharedPrefsLastGroupStore implements LastGroupStore {
  new([SharedPreferencesAsync? prefs]) : _prefs = prefs;

  static const _key = 'friends.last_group_id';

  SharedPreferencesAsync? _prefs;

  SharedPreferencesAsync get _store => _prefs ??= SharedPreferencesAsync();

  @override
  Future<String?> read() async {
    try {
      return await _store.getString(_key);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String groupId) async {
    try {
      await _store.setString(_key, groupId);
    } on Object {
      // Only a convenience.
    }
  }

  @override
  Future<void> forget(String groupId) async {
    try {
      if (await _store.getString(_key) == groupId) await _store.remove(_key);
    } on Object {
      // Only a convenience.
    }
  }
}

/// The app-wide [LastGroupStore]. Tests override it with an
/// in-memory store.
@Riverpod(keepAlive: true)
LastGroupStore lastGroupStore(Ref ref) => SharedPrefsLastGroupStore();
