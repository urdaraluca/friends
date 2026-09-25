// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/group.dart';
import '../models/invite.dart';
import '../models/invite_create.dart';
import '../models/invite_preview.dart';

part 'invites_client.g.dart';

@RestApi()
abstract class InvitesClient {
  factory InvitesClient(Dio dio, {String? baseUrl}) = _InvitesClient;

  /// List Invites.
  ///
  /// Newest first (at most 100). Admins see every invite, members only their own.
  @GET('/api/v1/groups/{group_id}/invites')
  Future<List<Invite>> listInvites({
    @Path('group_id') required String groupId,
  });

  /// Create Invite
  @POST('/api/v1/groups/{group_id}/invites')
  Future<Invite> createInvite({
    @Path('group_id') required String groupId,
    @Body() required InviteCreate body,
  });

  /// Revoke Invite.
  ///
  /// Idempotent.
  @DELETE('/api/v1/groups/{group_id}/invites/{invite_id}')
  Future<void> revokeInvite({
    @Path('invite_id') required String inviteId,
    @Path('group_id') required String groupId,
  });

  /// Preview Invite.
  ///
  /// Public: shows which group an invite is for and whether it can still be used.
  @GET('/api/v1/invites/{code}')
  Future<InvitePreview> previewInvite({
    @Path('code') required String code,
  });

  /// Accept Invite.
  ///
  /// Joins the group as a member. Accepting again when already a member changes nothing.
  @POST('/api/v1/invites/{code}/accept')
  Future<Group> acceptInvite({
    @Path('code') required String code,
  });
}
