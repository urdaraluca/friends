import 'package:friends/core/push/web_push_io.dart'
    if (dart.library.js_interop) 'package:friends/core/push/web_push_web.dart'
    as platform;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'web_push.g.dart';

/// A browser's push subscription, as `PUT /me/push-subscription` takes it.
class BrowserPushSubscription {
  const new({required this.endpoint, required this.p256dh, required this.auth});

  final String endpoint;
  final String p256dh;
  final String auth;
}

/// The browser's notification permission.
enum PushPermission { granted, denied, prompt, unsupported }

/// Browser push (contract section 18.6): only on the web, where the browser
/// supports service workers, the Push API and notifications. A provider so
/// tests use a fake.
class WebPush {
  const new();

  bool get supported => platform.supported();

  PushPermission get permission => switch (platform.permission()) {
    'granted' => PushPermission.granted,
    'denied' => PushPermission.denied,
    'default' => PushPermission.prompt,
    _ => PushPermission.unsupported,
  };

  /// This browser's current subscription, if any.
  Future<BrowserPushSubscription?> current() => platform.current();

  /// Asks for permission (if needed) and subscribes with the server's
  /// [vapidPublicKey]. Null when permission is refused.
  Future<BrowserPushSubscription?> subscribe(String vapidPublicKey) =>
      platform.subscribe(vapidPublicKey);

  /// Drops this browser's subscription; returns its endpoint, if it had one.
  Future<String?> unsubscribe() => platform.unsubscribe();
}

@Riverpod(keepAlive: true)
WebPush webPush(Ref ref) => const WebPush();
