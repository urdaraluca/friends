import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:material_ui/material_ui.dart';

/// Messages for problem codes of group, member and invite mutations.
const groupErrorMessages = <String, String>{
  ErrorCodes.forbidden: "You don't have permission to do that any more.",
  ErrorCodes.notFound: 'That no longer exists. The group has been reloaded.',
  ErrorCodes.limitReached: 'This group is full (100 members at most).',
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
