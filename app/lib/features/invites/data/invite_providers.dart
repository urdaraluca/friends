import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'invite_providers.g.dart';

/// The public preview of the invite [code] (`GET /invites/{code}`), in any
/// status. [code] must be normalized (`InviteCode.parse`); an unknown code
/// is a 404 `ProblemException`.
@riverpod
Future<InvitePreview> invitePreview(Ref ref, String code) {
  final client = ref.watch(publicInvitesClientProvider);
  return apiCall(() => client.previewInvite(code: code));
}
