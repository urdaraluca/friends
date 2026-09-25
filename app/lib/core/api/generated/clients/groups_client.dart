// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/group.dart';
import '../models/group_create.dart';
import '../models/group_summary.dart';
import '../models/group_update.dart';
import '../models/member.dart';
import '../models/member_settings_update.dart';
import '../models/role_update.dart';
import '../models/transfer_ownership.dart';

part 'groups_client.g.dart';

@RestApi()
abstract class GroupsClient {
  factory GroupsClient(Dio dio, {String? baseUrl}) = _GroupsClient;

  /// List Groups.
  ///
  /// My groups, by name.
  @GET('/api/v1/groups')
  Future<List<GroupSummary>> listGroups();

  /// Create Group.
  ///
  /// Creates a group owned by the caller.
  @POST('/api/v1/groups')
  Future<Group> createGroup({
    @Body() required GroupCreate body,
  });

  /// Get Group
  @GET('/api/v1/groups/{group_id}')
  Future<Group> getGroup({
    @Path('group_id') required String groupId,
  });

  /// Update Group
  @PUT('/api/v1/groups/{group_id}')
  Future<Group> updateGroup({
    @Path('group_id') required String groupId,
    @Body() required GroupUpdate body,
  });

  /// Delete Group
  @DELETE('/api/v1/groups/{group_id}')
  Future<void> deleteGroup({
    @Path('group_id') required String groupId,
  });

  /// Transfer Ownership.
  ///
  /// The target becomes owner; the caller becomes admin.
  @POST('/api/v1/groups/{group_id}/transfer-ownership')
  Future<Group> transferOwnership({
    @Path('group_id') required String groupId,
    @Body() required TransferOwnership body,
  });

  /// List Members.
  ///
  /// Owner, then admins, then members; each by name.
  @GET('/api/v1/groups/{group_id}/members')
  Future<List<Member>> listMembers({
    @Path('group_id') required String groupId,
  });

  /// Update My Member Settings
  @PUT('/api/v1/groups/{group_id}/members/me/settings')
  Future<Member> updateMyMemberSettings({
    @Path('group_id') required String groupId,
    @Body() required MemberSettingsUpdate body,
  });

  /// Update Member Role
  @PUT('/api/v1/groups/{group_id}/members/{user_id}/role')
  Future<Member> updateMemberRole({
    @Path('user_id') required String userId,
    @Path('group_id') required String groupId,
    @Body() required RoleUpdate body,
  });

  /// Remove Member.
  ///
  /// Removes a member, or leaves the group when ``user_id`` is the caller.
  ///
  /// The only member leaving deletes the group.
  @DELETE('/api/v1/groups/{group_id}/members/{user_id}')
  Future<void> removeMember({
    @Path('user_id') required String userId,
    @Path('group_id') required String groupId,
  });
}
