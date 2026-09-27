import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/invites/invite_code.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/core/widgets/form_widgets.dart';
import 'package:friends/features/groups/data/groups_controller.dart';
import 'package:friends/features/groups/presentation/widgets/group_avatar.dart';
import 'package:friends/features/invites/data/invite_providers.dart';
import 'package:friends/features/invites/presentation/invite_labels.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Public landing page of an invite link (`/join/:code`).
///
/// Shows the invite preview (`GET /invites/{code}`): the group, who
/// invited me and until when, or why the invite can't be used. Signed in,
/// "Join" accepts the invite and opens the group; signed out, "Log in" and
/// "Create account" come back here (`from`), and the register form gets the
/// code.
class JoinScreen extends ConsumerWidget {
  const new({required this.code, super.key});

  /// The code from the link, in any spelling.
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final normalized = InviteCode.parse(code);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.invite),
        leading: context.canPop()
            ? null
            : IconButton(
                tooltip: context.l10n.home,
                icon: const Icon(Icons.home_outlined),
                onPressed: () => context.go(Routes.home),
              ),
      ),
      body: FormPage(
        child: normalized == null
            ? _Message(
                icon: Icons.link_off,
                title: context.l10n.inviteLinkWrong,
                message: context.l10n.inviteLinkWrongHelp,
              )
            : _Preview(code: normalized),
      ),
    );
  }
}

class _Preview extends ConsumerWidget {
  const new({required this.code});

  /// The normalized code.
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(invitePreviewProvider(code));
    if (preview case AsyncError(:final error) when _isNotFound(error)) {
      return _Message(
        icon: Icons.search_off,
        title: context.l10n.inviteNotFound,
        message: context.l10n.inviteNotFoundHelp(InviteCode.format(code)),
      );
    }
    return AsyncValueView(
      value: preview,
      onRetry: () => ref.invalidate(invitePreviewProvider(code)),
      data: (preview) => _PreviewCard(preview: preview),
    );
  }

  static bool _isNotFound(Object error) => switch (ApiException.from(error)) {
    ProblemException(status: 404) => true,
    _ => false,
  };
}

class _PreviewCard extends ConsumerWidget {
  const new({required this.preview});

  final InvitePreview preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final group = preview.group;
    final count = group.memberCount;
    final invitedBy = preview.invitedByName;
    final problem = inviteUnusableReason(preview.status);
    final signedIn = ref.watch(currentUserIdProvider) != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          problem == null
              ? context.l10n.invitedToGroup
              : context.l10n.inviteToGroup,
          style: textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                GroupAvatar(
                  name: group.name,
                  emoji: group.emoji,
                  color: group.color,
                  radius: 36,
                ),
                const SizedBox(height: 12),
                Text(
                  group.name,
                  style: textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(context.l10n.memberCount(count)),
                if (invitedBy != null) ...[
                  const SizedBox(height: 12),
                  Text(context.l10n.invitedBy(invitedBy)),
                ],
                const SizedBox(height: 4),
                Text(
                  inviteExpiryLabel(preview.expiresAt),
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                SelectableText(
                  InviteCode.format(preview.code),
                  style: textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (problem != null) ...[
          FormMessageBanner(message: problem),
          const SizedBox(height: 16),
          if (signedIn)
            OutlinedButton(
              onPressed: () => context.go(Routes.groups),
              child: Text(context.l10n.goToMyGroups),
            )
          else
            OutlinedButton(
              onPressed: () => context.go(Routes.loginWith()),
              child: Text(context.l10n.logIn),
            ),
        ] else if (signedIn)
          _JoinButton(code: preview.code, groupName: group.name)
        else ...[
          FilledButton(
            onPressed: () => context.go(
              Routes.registerWith(
                from: Routes.join(preview.code),
                invite: preview.code,
              ),
            ),
            child: Text(context.l10n.createAccount),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () =>
                context.go(Routes.loginWith(from: Routes.join(preview.code))),
            child: Text(context.l10n.logIn),
          ),
        ],
      ],
    );
  }
}

/// "Join": accepts the invite, then opens the group's backlog.
class _JoinButton extends ConsumerStatefulWidget {
  const new({required this.code, required this.groupName});

  final String code;
  final String groupName;

  @override
  ConsumerState<_JoinButton> createState() => _JoinButtonState();
}

class _JoinButtonState extends ConsumerState<_JoinButton> {
  static Map<String, String> get _messages => {
    ErrorCodes.notFound: currentL10n.inviteNotFound,
    ErrorCodes.limitReached: currentL10n.joinLimitReached,
  };

  bool _joining = false;
  String? _error;

  Future<void> _join() async {
    setState(() {
      _joining = true;
      _error = null;
    });
    final router = GoRouter.of(context);
    try {
      final group = await ref
          .read(groupsControllerProvider.notifier)
          .acceptInvite(widget.code);
      router.go(Routes.groupBacklog(group.id));
    } on ApiException catch (e) {
      if (!mounted) return;
      // The invite may have changed meanwhile (expired, revoked, used up).
      ref.invalidate(invitePreviewProvider(widget.code));
      setState(() => _error = friendlyErrorMessage(e, messages: _messages));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error case final error?) ...[
          FormMessageBanner(message: error),
          const SizedBox(height: 16),
        ],
        SubmitButton(
          label: context.l10n.joinGroup(widget.groupName),
          busy: _joining,
          onPressed: _join,
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const new({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(icon, size: 56),
        const SizedBox(height: 16),
        Text(title, style: textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => context.go(Routes.home),
          child: Text(context.l10n.openFriends),
        ),
      ],
    );
  }
}
