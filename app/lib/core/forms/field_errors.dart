import 'package:flutter/foundation.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:material_ui/material_ui.dart';

/// Server-side field errors of a problem response, keyed by the problem's
/// dotted `field` path (`email`, `birthday.day`, `links.2.url`; body fields
/// have no `body.` prefix, contract section 1.5).
@immutable
class FieldErrors {
  const new([this._messages = const {}]);

  /// Field errors of [error] if it is a [ProblemException], else [none].
  ///
  /// [codeFields] puts errors that come without `errors[]` onto a field, e.g.
  /// `{ErrorCodes.emailTaken: 'email'}`. Their text is `messages[code]` or
  /// the [friendlyErrorMessage].
  factory fromError(
    Object error, {
    Map<String, String> codeFields = const {},
    Map<String, String> messages = const {},
  }) {
    final exception = ApiException.from(error);
    if (exception is! ProblemException) return none;
    final result = <String, String>{};
    for (final fieldError in exception.errors) {
      result.putIfAbsent(fieldError.field, () => fieldError.message);
    }
    final codeField = codeFields[exception.code];
    if (codeField != null && !result.containsKey(codeField)) {
      result[codeField] =
          messages[exception.code] ?? friendlyErrorMessage(exception);
    }
    return FieldErrors(Map.unmodifiable(result));
  }

  /// No errors.
  static const none = FieldErrors();

  final Map<String, String> _messages;

  bool get isEmpty => _messages.isEmpty;

  bool get isNotEmpty => _messages.isNotEmpty;

  /// Every field path that has an error.
  Iterable<String> get fields => _messages.keys;

  /// The message for [field] or for a nested path below it (`birthday`
  /// also matches `birthday.day`), or null.
  String? operator [](String field) {
    final exact = _messages[field];
    if (exact != null) return exact;
    for (final MapEntry(:key, :value) in _messages.entries) {
      if (key.startsWith('$field.')) return value;
    }
    return null;
  }

  /// Whether [field] (or a path below it) has an error.
  bool has(String field) => this[field] != null;

  /// These errors without [field] and the paths below it.
  FieldErrors without(String field) {
    if (!has(field)) return this;
    return FieldErrors(
      Map.unmodifiable({
        for (final MapEntry(:key, :value) in _messages.entries)
          if (key != field && !key.startsWith('$field.')) key: value,
      }),
    );
  }

  /// `field: message` for every error whose field isn't covered by any of
  /// [shownFields]; show them in a banner so no server error is lost.
  List<String> unclaimed(Iterable<String> shownFields) => [
    for (final MapEntry(:key, :value) in _messages.entries)
      if (!shownFields.any((f) => key == f || key.startsWith('$f.')))
        '$key: $value',
  ];

  @override
  bool operator ==(Object other) =>
      other is FieldErrors && mapEquals(other._messages, _messages);

  @override
  int get hashCode => Object.hashAllUnordered(
    _messages.entries.map((e) => Object.hash(e.key, e.value)),
  );

  @override
  String toString() => 'FieldErrors($_messages)';
}

/// Shows API errors on a form: field errors on their fields, the rest in a
/// banner ([formError]).
///
/// ```dart
/// class _MyFormState extends State<MyForm> with ServerErrorsMixin {
///   Future<void> _submit() async {
///     clearFormError();
///     if (!_formKey.currentState!.validate()) return;
///     try {
///       await save();
///     } on ApiException catch (e) {
///       showServerError(e, fields: const {'name', 'email'});
///     }
///   }
///
///   // in build():
///   TextFormField(
///     forceErrorText: serverError('email'),
///     onChanged: (_) => clearServerError('email'),
///   ),
///   if (formError case final message?) FormMessageBanner(message: message),
/// }
/// ```
///
/// A field keeps its server error until the user edits it, because
/// `forceErrorText` takes precedence over the field's validator.
mixin ServerErrorsMixin<T extends StatefulWidget> on State<T> {
  FieldErrors _fieldErrors = FieldErrors.none;
  String? _formError;

  /// The server's field errors currently shown.
  FieldErrors get fieldErrors => _fieldErrors;

  /// The message for the form's error banner, or null.
  String? get formError => _formError;

  /// The server's message for [field], for `TextFormField.forceErrorText`.
  String? serverError(String field) => _fieldErrors[field];

  /// Clears the server error of [field]; call it from the field's
  /// `onChanged`.
  void clearServerError(String field) {
    if (!_fieldErrors.has(field)) return;
    setState(() => _fieldErrors = _fieldErrors.without(field));
  }

  /// Clears the banner (call it when submitting again).
  void clearFormError() {
    if (_formError == null) return;
    setState(() => _formError = null);
  }

  /// Clears every server error.
  void clearServerErrors() => setState(() {
    _fieldErrors = FieldErrors.none;
    _formError = null;
  });

  /// Shows [error]: messages for [fields] go on those fields, anything else
  /// (network errors, other codes, errors for fields the form doesn't show)
  /// goes to [formError]. See [FieldErrors.fromError] for [codeFields] and
  /// [messages].
  void showServerError(
    Object error, {
    required Set<String> fields,
    Map<String, String> codeFields = const {},
    Map<String, String> messages = const {},
  }) {
    final all = FieldErrors.fromError(
      error,
      codeFields: codeFields,
      messages: messages,
    );
    var shown = all;
    for (final field in all.fields.toList()) {
      if (!fields.any((f) => field == f || field.startsWith('$f.'))) {
        shown = shown.without(field);
      }
    }
    final unclaimed = all.unclaimed(fields);
    setState(() {
      _fieldErrors = shown;
      _formError = unclaimed.isNotEmpty
          ? unclaimed.join('\n')
          : shown.isEmpty
          ? friendlyErrorMessage(error, messages: messages)
          : null;
    });
  }
}
