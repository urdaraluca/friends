import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/links/open_link.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/core/widgets/confirm_dialog.dart';
import 'package:friends/features/calendar/data/calendar_feed_providers.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Subscribing to my calendar from Google Calendar, Apple Calendar or
/// Outlook (contract section 5.10): turn the webcal feed on, open or copy
/// its secret link, reset it, or turn it off.
class CalendarFeedScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(calendarFeedControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.calendarFeed)),
      body: AsyncValueView(
        value: feed,
        onRetry: () => ref.invalidate(calendarFeedControllerProvider),
        data: (feed) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(context.l10n.calendarFeedIntro),
                const SizedBox(height: 16),
                _FeedActions(feed: feed),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedActions extends ConsumerStatefulWidget {
  const new({required this.feed});

  final CalendarFeed feed;

  @override
  ConsumerState<_FeedActions> createState() => _FeedActionsState();
}

class _FeedActionsState extends ConsumerState<_FeedActions> {
  bool _busy = false;

  CalendarFeedController get _controller =>
      ref.read(calendarFeedControllerProvider.notifier);

  /// Runs [action], then shows [done] (if any) or the error.
  Future<void> _run(Future<void> Function() action, {String? done}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      if (done != null) {
        messenger.showSnackBar(SnackBar(content: Text(done)));
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final l10n = context.l10n;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.calendarFeedResetTitle,
      message: l10n.calendarFeedResetMessage,
      confirmLabel: l10n.calendarFeedReset,
    );
    if (confirmed) {
      await _run(_controller.reset, done: l10n.calendarFeedResetDone);
    }
  }

  Future<void> _turnOff() async {
    final l10n = context.l10n;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.calendarFeedTurnOffTitle,
      message: l10n.calendarFeedTurnOffMessage,
      confirmLabel: l10n.calendarFeedTurnOff,
      destructive: true,
    );
    if (confirmed) {
      await _run(_controller.disable, done: l10n.calendarFeedTurnedOff);
    }
  }

  Future<void> _copy(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final copied = context.l10n.calendarFeedCopied;
    await Clipboard.setData(ClipboardData(text: url));
    messenger.showSnackBar(SnackBar(content: Text(copied)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final url = widget.feed.url;
    final webcalUrl = widget.feed.webcalUrl;
    if (url == null || webcalUrl == null) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.icon(
          onPressed: _busy ? null : () => unawaited(_run(_controller.reset)),
          icon: const Icon(Icons.event_repeat),
          label: Text(l10n.calendarFeedTurnOn),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(url, style: textTheme.bodySmall),
          ),
        ),
        const SizedBox(height: 8),
        Text(l10n.calendarFeedPrivateNote, style: textTheme.bodySmall),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () =>
                  unawaited(openLink(context, ref, Uri.parse(webcalUrl))),
              icon: const Icon(Icons.event_available),
              label: Text(l10n.calendarFeedAdd),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(_copy(url)),
              icon: const Icon(Icons.copy),
              label: Text(l10n.calendarFeedCopy),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(l10n.calendarFeedGoogleHint, style: textTheme.bodySmall),
        const SizedBox(height: 24),
        const Divider(),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton.icon(
              onPressed: _busy ? null : () => unawaited(_reset()),
              icon: const Icon(Icons.refresh),
              label: Text(l10n.calendarFeedReset),
            ),
            TextButton.icon(
              onPressed: _busy ? null : () => unawaited(_turnOff()),
              icon: const Icon(Icons.link_off),
              label: Text(l10n.calendarFeedTurnOff),
            ),
          ],
        ),
      ],
    );
  }
}
