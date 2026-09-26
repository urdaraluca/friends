import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/auth/token_store.dart';
import 'package:mocktail/mocktail.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage;

void main() {
  late _MockSecureStorage storage;
  late SecureTokenStore store;

  setUp(() {
    storage = _MockSecureStorage();
    store = SecureTokenStore(storage);
  });

  group('SecureTokenStore', () {
    test('reads, writes and deletes one key', () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => 'refresh-1');
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {});
      when(() => storage.delete(key: any(named: 'key')))
          .thenAnswer((_) async {});

      expect(await store.readRefreshToken(), 'refresh-1');
      await store.writeRefreshToken('refresh-2');
      await store.clear();

      verifyInOrder([
        () => storage.read(key: 'friends.refresh_token'),
        () => storage.write(key: 'friends.refresh_token', value: 'refresh-2'),
        () => storage.delete(key: 'friends.refresh_token'),
      ]);
    });

    test('an unreadable store (a reset keystore) means no session', () async {
      when(() => storage.read(key: any(named: 'key')))
          .thenThrow(PlatformException(code: 'BAD_DECRYPT'));

      expect(await store.readRefreshToken(), isNull);
    });
  });
}
