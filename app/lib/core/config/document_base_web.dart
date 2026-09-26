import 'dart:js_interop';

@JS('document.baseURI')
external String get _baseUri;

/// The page's `<base href>`, resolved: e.g. `https://example.com/friends/`.
///
/// Unlike [Uri.base] (the current page), it stays the same on every route.
Uri documentBaseUri() => Uri.parse(_baseUri);
