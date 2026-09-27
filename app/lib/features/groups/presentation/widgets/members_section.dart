import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/widgets/confirm_dialog.dart';
import 'package:friends/features/groups/data/groups_controller.dart';
import 'package:friends/features/groups/domain/group_permissions.dart';
import 'package:friends/features/groups/presentation/widgets/group_action.dart';
import 'package:friends/features/groups/presentation/widgets/role_badge.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// "12 March" for a member's shared birthday.
String formatBirthday(BirthdayPublic birthday) =>
    // 2000 is a leap year, so 29 February formats too.
    DateFormat.MMMMd().format(DateTime(2000, birthday.month, birthday.day));

/// The group's members with their role badges and shared birthdays, and
/// the actions [permissions] allow on each (contract section 7.2).
class MembersList extends StatelessWidget {
  const new({
    required this.group,
    required this.members,
    required this.permissions,
    super.key,
  });

  final Group group;
  final List<Member> members;
  final GroupPermissions permissions;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final member in members)
          MemberTile(group: group, member: member, permissions: permissions),
      ],
    );
  }
}

enum _MemberAction { makeAdmin, makeMember, transfer, remove }

class MemberTile extends ConsumerWidget {
  const new({
    required this.group,
    required this.member,
    required this.permissions,
    super.key,
  });

  final Group group;
  final Member member;
  final GroupPermissions permissions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = member.user.displayName;
    final isMe = permissions.isMe(member);
    final birthday = member.birthday;
    final actions = [
      if (permissions.canChangeRoleOf(member))
        if (member.role == Role.admin)
          _MemberAction.makeMember
        else
          _MemberAction.makeAdmin,
      if (permissions.canTransferTo(member)) _MemberAction.transfer,
      if (permissions.canRemove(member)) _MemberAction.remove,
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: Text(
          name.trim().isEmpty
              ? '?'
              : String.fromCharCode(name.trim().runes.first).toUpperCase(),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              isMe ? context.l10n.memberYou(name) : name,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          RoleBadge(member.role),
        ],
      ),
      subtitle: birthday == null
          ? null
          : Text(context.l10n.birthdayOn(formatBirthday(birthday))),
      trailing: actions.isEmpty
          ? null
          : PopupMenuButton<_MemberAction>(
              tooltip: context.l10n.actionsFor(name),
              onSelected: (action) => unawaited(
                _run(
                  context,
                  ref.read(groupsControllerProvider.notifier),
                  action,
                ),
              ),
              itemBuilder: (context) => [
                for (final action in actions)
                  PopupMenuItem(
                    value: action,
                    child: Text(switch (action) {
                      _MemberAction.makeAdmin => context.l10n.makeAdmin,
                      _MemberAction.makeMember => context.l10n.makeMember,
                      _MemberAction.transfer => context.l10n.transferOwnership,
                      _MemberAction.remove => context.l10n.removeFromGroup,
                    }),
                  ),
              ],
            ),
    );
  }

  Future<void> _run(
    BuildContext context,
    GroupsController controller,
    _MemberAction action,
  ) async {
    final l10n = context.l10n;
    final name = member.user.displayName;
    final userId = member.user.id;
    switch (action) {
      case _MemberAction.makeAdmin:
        await runGroupAction(
          context,
          () => controller.changeRole(group.id, userId, AssignableRole.admin),
          success: l10n.nowAdmin(name),
        );
      case _MemberAction.makeMember:
        await runGroupAction(
          context,
          () => controller.changeRole(group.id, userId, AssignableRole.member),
          success: l10n.nowMember(name),
        );
      case _MemberAction.transfer:
        final confirmed = await showConfirmDialog(
          context,
          title: l10n.makeOwnerTitle(name),
          message: l10n.makeOwnerMessage(name, group.name),
          confirmLabel: l10n.transferOwnership,
        );
        if (!confirmed || !context.mounted) return;
        await runGroupAction(
          context,
          () => controller.transferOwnership(group.id, userId),
          success: l10n.nowOwner(name),
        );
      case _MemberAction.remove:
        final confirmed = await showConfirmDialog(
          context,
          title: l10n.removeMemberTitle(name),
          message: l10n.removeMemberMessage(name, group.name),
          confirmLabel: l10n.remove,
          destructive: true,
        );
        if (!confirmed || !context.mounted) return;
        await runGroupAction(
          context,
          () => controller.removeMember(group.id, userId),
          success: l10n.memberRemoved(name),
        );
    }
  }
}

/// My settings in this group: whether my birthday is shown to it
/// (`PUT /groups/{id}/members/me/settings`).
class MySettingsTile extends ConsumerStatefulWidget {
  const new({required this.groupId, required this.me, super.key});

  final String groupId;

  /// My member row (its `show_birthday` is my setting).
  final Member me;

  @override
  ConsumerState<MySettingsTile> createState() => _MySettingsTileState();
}

class _MySettingsTileState extends ConsumerState<MySettingsTile> {
  /// The value being saved, shown until the members list reloads.
  bool? _pending;

  Future<void> _set(bool value) async {
    setState(() => _pending = value);
    await runGroupAction(
      context,
      () => ref
          .read(groupsControllerProvider.notifier)
          .updateMySettings(widget.groupId, showBirthday: value),
    );
    if (mounted) setState(() => _pending = null);
  }

  @override
  Widget build(BuildContext context) {
    final hasBirthday = ref.watch(currentUserProvider)?.birthday != null;
    final value = _pending ?? widget.me.showBirthday ?? false;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(context.l10n.showMyBirthday),
      subtitle: Text(
        hasBirthday
            ? context.l10n.showMyBirthdayHelp
            : context.l10n.addBirthdayFirst,
      ),
      value: value,
      onChanged: _pending != null ? null : (value) => unawaited(_set(value)),
    );
  }
}
