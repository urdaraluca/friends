import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'device_info.g.dart';

/// The `device_label` sent at login and registration: `android`, `ios`,
/// `web`, or the platform's name elsewhere.
@Riverpod(keepAlive: true)
String deviceLabel(Ref ref) {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    final platform => platform.name,
  };
}

/// The device's IANA timezone (e.g. `Europe/Bucharest`), or `UTC` when the
/// platform can't tell.
@Riverpod(keepAlive: true)
Future<String> deviceTimezone(Ref ref) async {
  try {
    final zone = (await FlutterTimezone.getLocalTimezone()).identifier;
    return zone.isEmpty ? 'UTC' : zone;
  } on Object {
    return 'UTC';
  }
}
