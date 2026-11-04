import 'package:friends/core/push/web_push.dart';

// Not on the web: the native apps have no push yet (contract section 18.6).

bool supported() => false;

String permission() => 'unsupported';

Future<BrowserPushSubscription?> current() async => null;

Future<BrowserPushSubscription?> subscribe(String vapidPublicKey) async => null;

Future<String?> unsubscribe() async => null;
