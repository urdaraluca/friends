/// Book languages (ISO 639-1 codes, contract section 17.2), named in their
/// own language ("Română", "Deutsch") so no name needs translating.
library;

/// The languages the form offers first.
const commonBookLanguages = [
  'ro',
  'en',
  'fr',
  'de',
  'it',
  'es',
  'hu',
  'pt',
  'ru',
];

/// Every language the "Other…" list offers, by code.
const bookLanguageNames = <String, String>{
  'ro': 'Română',
  'en': 'English',
  'fr': 'Français',
  'de': 'Deutsch',
  'it': 'Italiano',
  'es': 'Español',
  'hu': 'Magyar',
  'pt': 'Português',
  'ru': 'Русский',
  'ar': 'العربية',
  'bg': 'Български',
  'ca': 'Català',
  'cs': 'Čeština',
  'da': 'Dansk',
  'el': 'Ελληνικά',
  'fi': 'Suomi',
  'he': 'עברית',
  'hi': 'हिन्दी',
  'hr': 'Hrvatski',
  'ja': '日本語',
  'ko': '한국어',
  'la': 'Latina',
  'nl': 'Nederlands',
  'no': 'Norsk',
  'pl': 'Polski',
  'sk': 'Slovenčina',
  'sl': 'Slovenščina',
  'sr': 'Српски',
  'sv': 'Svenska',
  'tr': 'Türkçe',
  'uk': 'Українська',
  'zh': '中文',
};

/// The name of the language with [code]; an unknown code is shown as it is,
/// uppercase ("EO").
String bookLanguageName(String code) =>
    bookLanguageNames[code] ?? code.toUpperCase();
