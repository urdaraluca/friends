import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/links/open_link.dart';
import 'package:friends/core/widgets/confirm_dialog.dart';
import 'package:friends/core/widgets/user_avatar.dart';
import 'package:friends/features/polls/data/polls_providers.dart';
import 'package:friends/features/polls/presentation/poll_dialogs.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// Messages for poll errors that the card shows next to its options.
const Map<String, String> pollErrorMessages = {
  ErrorCodes.pollClosed: 'This poll just closed.',
  ErrorCodes.tooManyChoices: 'This poll takes one choice only.',
  ErrorCodes.limitReached: 'A poll has 2 to 20 options.',
  ErrorCodes.nameTaken: 'That option is already in the poll.',
};

/// One poll (contract sections 8.9 and 9): the question, whether it is open
/// and until when (device-local time), each option with its vote bar, count
/// and voters, the winners highlighted, and my vote.
///
/// Single choice: radio buttons, sent at once. Multiple choice: checkboxes
/// and "Save vote" (`PUT /polls/{id}/votes/me` replaces my whole vote; an
/// empty set retracts it). Managers (`can_manage`) edit, close, reopen and
/// delete; anyone adds options while it is open.
class PollCard extends ConsumerStatefulWidget {
  const new({required this.poll, super.key});

  final Poll poll;

  @override
  ConsumerState<PollCard> createState() => _PollCardState();
}

class _PollCardState extends ConsumerState<PollCard> {
  /// Checked options of a multiple-choice poll not saved yet, else null.
  Set<String>? _draft;
  bool _busy = false;
  String? _error;

  Poll get _poll => widget.poll;

  @override
  void didUpdateWidget(PollCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!setEquals(
      oldWidget.poll.myOptionIds.toSet(),
      _poll.myOptionIds.toSet(),
    )) {
      _draft = null;
    }
  }

  PollsController get _controller => ref.read(pollsControllerProvider.notifier);

  Future<void> _run(Future<Object?> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) setState(() => _draft = null);
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error case ProblemException(code: ErrorCodes.pollClosed)) {
        _controller.refresh(_poll.activityId);
      }
      setState(
        () => _error = friendlyErrorMessage(error, messages: pollErrorMessages),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _vote(List<String> optionIds) =>
      _run(() => _controller.vote(_poll, optionIds));

  Future<void> _manage(String action) async {
    switch (action) {
      case 'edit':
        final body = await showEditPollDialog(context, _poll);
        if (body != null) await _run(() => _controller.update(_poll, body));
      case 'close':
        await _run(() => _controller.close(_poll));
      case 'reopen':
        await _run(() => _controller.reopen(_poll));
      case 'delete':
        final confirmed = await showConfirmDialog(
          context,
          title: 'Delete this poll?',
          message: 'Its options and votes go with it.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (confirmed) await _run(() => _controller.delete(_poll));
    }
  }

  Future<void> _addOption() async {
    final body = await showAddOptionDialog(context);
    if (body != null) await _run(() => _controller.addOption(_poll, body));
  }

  Future<void> _deleteOption(PollOption option) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove "${option.label}"?',
      message: option.voteCount == 0
          ? 'Nobody has voted for it yet.'
          : 'Its ${option.voteCount} votes are removed too.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (confirmed) await _run(() => _controller.deleteOption(_poll, option.id));
  }

  String _statusText() {
    final format = DateFormat('EEE d MMM, HH:mm');
    if (!_poll.isOpen) {
      final closed = _poll.closedAt ?? _poll.closesAt;
      return closed == null
          ? 'Closed'
          : 'Closed ${format.format(closed.toLocal())}';
    }
    final closesAt = _poll.closesAt;
    return closesAt == null
        ? 'Open'
        : 'Open until ${format.format(closesAt.toLocal())}';
  }

  @override
  Widget build(BuildContext context) {
    final poll = _poll;
    final theme = Theme.of(context);
    final mine = poll.myOptionIds.toSet();
    final selected = _draft ?? mine;
    final maxVotes = poll.options.map((o) => o.voteCount).fold(0, max);
    final canVote = poll.isOpen && !_busy;
    final voters =
        '${poll.totalVoters} ${poll.totalVoters == 1 ? 'voter' : 'voters'}';
    final dirty = _draft != null && !setEquals(_draft, mine);

    Widget optionRow(PollOption option) {
      final winner = poll.winningOptionIds.contains(option.id);
      final share = maxVotes == 0 ? 0.0 : option.voteCount / maxVotes;
      final control = poll.allowMultiple
          ? Checkbox(
              value: selected.contains(option.id),
              onChanged: canVote
                  ? (on) => setState(() {
                      // The latest selection, even if two changes come
                      // before a rebuild.
                      final next = {...(_draft ?? _poll.myOptionIds)};
                      if (on ?? false) {
                        next.add(option.id);
                      } else {
                        next.remove(option.id);
                      }
                      _draft = next;
                    })
                  : null,
            )
          : Radio<String>(value: option.id, enabled: canVote);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            control,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (winner) ...[
                        Icon(
                          Icons.emoji_events,
                          size: 18,
                          color: theme.colorScheme.tertiary,
                          semanticLabel: 'Winning',
                        ),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          option.label,
                          style: winner
                              ? const TextStyle(fontWeight: FontWeight.bold)
                              : null,
                        ),
                      ),
                      if (option.url case final url?)
                        IconButton(
                          tooltip: 'Open link',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.open_in_new, size: 18),
                          onPressed: () {
                            final uri = Uri.tryParse(url);
                            if (uri != null) {
                              unawaited(openLink(context, ref, uri));
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: share,
                      minHeight: 6,
                      color: winner
                          ? theme.colorScheme.tertiary
                          : theme.colorScheme.primary,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('${option.voteCount}', style: theme.textTheme.titleSmall),
            const SizedBox(width: 8),
            AvatarStack(users: option.voters, max: 3, radius: 10),
            if (option.canDelete)
              IconButton(
                tooltip: 'Remove "${option.label}"',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: _busy
                    ? null
                    : () => unawaited(_deleteOption(option)),
              ),
          ],
        ),
      );
    }

    final options = Column(
      children: [for (final option in poll.options) optionRow(option)],
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(poll.question, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        [
                          _statusText(),
                          if (poll.allowMultiple) 'multiple choice',
                          voters,
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (poll.canManage)
                  PopupMenuButton<String>(
                    tooltip: 'Manage poll',
                    enabled: !_busy,
                    onSelected: (action) => unawaited(_manage(action)),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      if (poll.isOpen)
                        const PopupMenuItem(
                          value: 'close',
                          child: Text('Close poll'),
                        )
                      else
                        const PopupMenuItem(
                          value: 'reopen',
                          child: Text('Reopen poll'),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete poll'),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (poll.allowMultiple)
              options
            else
              RadioGroup<String>(
                groupValue: mine.firstOrNull,
                onChanged: (id) {
                  if (id != null && canVote) unawaited(_vote([id]));
                },
                child: options,
              ),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
                child: Text(
                  error,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            Wrap(
              spacing: 8,
              children: [
                if (poll.allowMultiple && poll.isOpen)
                  FilledButton.tonal(
                    onPressed: dirty && !_busy
                        ? () => unawaited(_vote(selected.toList()))
                        : null,
                    child: const Text('Save vote'),
                  ),
                if (poll.isOpen && mine.isNotEmpty && !dirty)
                  TextButton(
                    onPressed: _busy ? null : () => unawaited(_vote(const [])),
                    child: const Text('Retract my vote'),
                  ),
                if (poll.isOpen && poll.options.length < 20)
                  TextButton.icon(
                    onPressed: _busy ? null : () => unawaited(_addOption()),
                    icon: const Icon(Icons.add),
                    label: const Text('Add option'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
