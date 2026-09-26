import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens web links and map searches outside the app. A provider, so tests
/// record what would be opened instead.
class LinkOpener {
  const new();

  /// Opens [url] in the browser (or the app that handles it).
  Future<bool> open(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  /// A map search for [query] (a place name or an address; there are no
  /// coordinates in the MVP).
  static Uri mapsSearch(String query) => Uri.https(
    'www.google.com',
    '/maps/search/',
    {'api': '1', 'query': query},
  );
}

/// The app's [LinkOpener].
final linkOpenerProvider = Provider<LinkOpener>((ref) => const LinkOpener());

/// Opens [url], telling the user when nothing could open it.
Future<void> openLink(BuildContext context, WidgetRef ref, Uri url) async {
  final messenger = ScaffoldMessenger.of(context);
  final opened = await ref
      .read(linkOpenerProvider)
      .open(url)
      .catchError((Object _) => false);
  if (!opened) {
    messenger.showSnackBar(
      SnackBar(content: Text("Couldn't open ${url.host}")),
    );
  }
}
