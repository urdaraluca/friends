import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Messages for problem codes of group, member and invite mutations.
Map<String, String> get groupErrorMessages => {
  ErrorCodes.forbidden: currentL10n.groupErrorForbidden,
  ErrorCodes.notFound: currentL10n.groupErrorNotFound,
  ErrorCodes.limitReached: currentL10n.groupErrorFull,
};

/// Runs a mutation from a screen: shows [success] in a snack bar when it
/// works, the friendly error otherwise. Returns whether it worked.
///
/// The snack bar outlives the screen, so this is safe to use when the
/// action navigates away.
Future<bool> runGroupAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
  Map<String, String> messages = const {},
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (success != null) {
      messenger.showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          friendlyErrorMessage(
            e,
            messages: {...groupErrorMessages, ...messages},
          ),
        ),
      ),
    );
    return false;
  }
}
