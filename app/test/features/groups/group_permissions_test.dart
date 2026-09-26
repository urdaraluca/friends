import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/features/groups/domain/group_permissions.dart';

import '../../helpers/api_fixtures.dart';

void main() {
  const me = Ids.anaId;

  GroupPermissions as(Role role, {bool membersCanInvite = true}) =>
      GroupPermissions(
        myRole: role,
        myUserId: me,
        membersCanInvite: membersCanInvite,
      );

  // `$unknown` stands for a role a newer server might send.
  Member member(Role role, {String id = Ids.beaId}) => Member.fromJson(
    memberJson(userId: id, displayName: 'X', role: role.json ?? 'guest'),
  );

  Invite invite({String createdBy = Ids.beaId}) =>
      Invite.fromJson(inviteJson(createdById: createdBy));

  // Contract section 7.2, row by row.
  group('GroupPermissions', () {
    test('edit group settings: admin+', () {
      expect(as(Role.member).canEditGroup, isFalse);
      expect(as(Role.admin).canEditGroup, isTrue);
      expect(as(Role.owner).canEditGroup, isTrue);
    });

    test('delete group, transfer ownership, change roles: owner', () {
      for (final role in [Role.member, Role.admin]) {
        expect(as(role).canDeleteGroup, isFalse);
        expect(as(role).canManageRoles, isFalse);
        expect(as(role).canTransferTo(member(Role.member)), isFalse);
        expect(as(role).canChangeRoleOf(member(Role.member)), isFalse);
      }
      final owner = as(Role.owner);
      expect(owner.canDeleteGroup, isTrue);
      expect(owner.canTransferTo(member(Role.member)), isTrue);
      expect(owner.canTransferTo(member(Role.admin)), isTrue);
      expect(owner.canChangeRoleOf(member(Role.member)), isTrue);
      expect(owner.canChangeRoleOf(member(Role.admin)), isTrue);
    });

    test("the owner's own role only changes through a transfer", () {
      final owner = as(Role.owner);
      final self = member(Role.owner, id: me);

      expect(owner.canChangeRoleOf(self), isFalse);
      expect(owner.canTransferTo(self), isFalse);
      expect(owner.canRemove(self), isFalse);
    });

    test('remove a member: admin+; remove an admin: owner; never the '
        'owner', () {
      expect(as(Role.member).canRemove(member(Role.member)), isFalse);
      expect(as(Role.member).canRemove(member(Role.admin)), isFalse);

      expect(as(Role.admin).canRemove(member(Role.member)), isTrue);
      expect(as(Role.admin).canRemove(member(Role.admin)), isFalse);
      expect(as(Role.admin).canRemove(member(Role.owner)), isFalse);

      expect(as(Role.owner).canRemove(member(Role.member)), isTrue);
      expect(as(Role.owner).canRemove(member(Role.admin)), isTrue);
    });

    test('removing yourself is leaving, not removing', () {
      expect(as(Role.admin).canRemove(member(Role.admin, id: me)), isFalse);
      expect(as(Role.member).canLeave, isTrue);
      expect(as(Role.owner).canLeave, isTrue);
    });

    test('create an invite: admin+, or anyone with members_can_invite', () {
      expect(as(Role.member).canCreateInvite, isTrue);
      expect(as(Role.member, membersCanInvite: false).canCreateInvite, isFalse);
      expect(as(Role.admin, membersCanInvite: false).canCreateInvite, isTrue);
      expect(as(Role.owner, membersCanInvite: false).canCreateInvite, isTrue);
    });

    test('never-expiring invites: admin+ only', () {
      expect(as(Role.member).canCreateNeverExpiringInvite, isFalse);
      expect(as(Role.admin).canCreateNeverExpiringInvite, isTrue);
      expect(as(Role.owner).canCreateNeverExpiringInvite, isTrue);
    });

    test('see invites: own for members, all for admin+', () {
      expect(as(Role.member).seesAllInvites, isFalse);
      expect(as(Role.admin).seesAllInvites, isTrue);
      expect(as(Role.owner).seesAllInvites, isTrue);
    });

    test('revoke an invite: own for members, any for admin+', () {
      expect(as(Role.member).canRevoke(invite(createdBy: me)), isTrue);
      expect(as(Role.member).canRevoke(invite()), isFalse);
      expect(as(Role.admin).canRevoke(invite()), isTrue);
      expect(as(Role.owner).canRevoke(invite()), isTrue);
    });

    test('an unknown role from a newer server gets the least', () {
      final unknown = as(Role.$unknown, membersCanInvite: false);

      expect(unknown.canEditGroup, isFalse);
      expect(unknown.canRemove(member(Role.member)), isFalse);
      expect(unknown.canCreateInvite, isFalse);
      expect(as(Role.owner).canRemove(member(Role.$unknown)), isFalse);
      expect(as(Role.owner).canChangeRoleOf(member(Role.$unknown)), isFalse);
    });
  });

  test('role labels', () {
    expect(Role.owner.label, 'Owner');
    expect(Role.admin.label, 'Admin');
    expect(Role.member.label, 'Member');
    expect(Role.owner.isAdminOrOwner, isTrue);
    expect(Role.member.isAdminOrOwner, isFalse);
  });
}
