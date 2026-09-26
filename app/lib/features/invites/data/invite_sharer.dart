import 'package:friends/core/api/generated/export.dart';
import 'package:material_ui/material_ui.dart' show Rect;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:share_plus/share_plus.dart';

part 'invite_sharer.g.dart';

/// Opens the platform's share sheet for an invite link (`share_plus`).
class InviteSharer {
  const new();

  /// The message shared for [invite] to the group [groupName].
  static String message(Invite invite, String groupName) =>
      'Join "$groupName" on Friends: ${invite.url}';

  /// Shares [invite]'s link. [origin] is where the sheet points from on
  /// iPad and macOS (the tapped button).
  Future<void> share(
    Invite invite, {
    required String groupName,
    Rect? origin,
  }) => SharePlus.instance.share(
    ShareParams(
      text: message(invite, groupName),
      subject: 'Join $groupName on Friends',
      sharePositionOrigin: origin,
    ),
  );
}

/// The app's [InviteSharer]. Tests override it to record what is shared.
@Riverpod(keepAlive: true)
InviteSharer inviteSharer(Ref ref) => const InviteSharer();
