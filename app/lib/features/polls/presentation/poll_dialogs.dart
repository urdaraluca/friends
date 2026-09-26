import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_instant.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/forms/field_errors.dart';
import 'package:friends/core/forms/validators.dart';
import 'package:friends/core/widgets/form_widgets.dart';
import 'package:friends/features/backlog/domain/field_values.dart';
import 'package:friends/features/polls/data/polls_providers.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// Options per poll (contract section 1.9).
const minPollOptions = 2;
const maxPollOptions = 20;

/// Labels compare the way the server does (ASCII-only case folding).
String _fold(String label) => label.trim().toLowerCase();

String? _optionalUrl(String? value) {
  final url = (value ?? '').trim();
  if (url.isEmpty) return null;
  return FieldValues.isWebUrl(url) ? null : 'Enter a full http(s) link';
}

/// Picks a date and a time in the future, in device-local time, or null.
Future<DateTime?> pickFutureDateTime(
  BuildContext context, {
  DateTime? initial,
}) async {
  final now = DateTime.now();
  final start = (initial ?? now.add(const Duration(days: 1))).toLocal();
  final date = await showDatePicker(
    context: context,
    initialDate: start.isBefore(now) ? now : start,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: DateTime(now.year + 5),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(start),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// A closing-time field: "No closing time" or the chosen instant, with a
/// picker and a clear button.
class ClosingTimeField extends StatelessWidget {
  const new({
    required this.value,
    required this.onChanged,
    this.error,
    super.key,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Closes',
        helperText: 'Voting stops then, automatically',
        errorText: error,
        suffixIcon: value == null
            ? null
            : IconButton(
                tooltip: 'No closing time',
                icon: const Icon(Icons.clear),
                onPressed: () => onChanged(null),
              ),
      ),
      child: InkWell(
        onTap: () async {
          final picked = await pickFutureDateTime(context, initial: value);
          if (picked != null) onChanged(picked);
        },
        child: Text(
          value == null
              ? 'No closing time'
              : DateFormat('EEE d MMM y, HH:mm').format(value.toLocal()),
        ),
      ),
    );
  }
}

/// Creates a poll on [activityId]; resolves once created (or dismissed).
Future<void> showCreatePollSheet(BuildContext context, String activityId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: CreatePollSheet(activityId: activityId),
    ),
  );
}

class _OptionDraft {
  final label = TextEditingController();
  final url = TextEditingController();

  void dispose() {
    label.dispose();
    url.dispose();
  }
}

/// The "New poll" sheet: a question (≤200), single or multiple choice
/// (fixed afterwards), an optional closing time in the future, and 2..20
/// options (labels ≤100, unique ignoring case) with optional links.
class CreatePollSheet extends ConsumerStatefulWidget {
  const new({required this.activityId, super.key});

  final String activityId;

  @override
  ConsumerState<CreatePollSheet> createState() => _CreatePollSheetState();
}

class _CreatePollSheetState extends ConsumerState<CreatePollSheet>
    with ServerErrorsMixin {
  final _formKey = GlobalKey<FormState>();
  final _question = TextEditingController();
  final List<_OptionDraft> _options = [_OptionDraft(), _OptionDraft()];
  bool _allowMultiple = false;
  DateTime? _closesAt;
  bool _saving = false;

  @override
  void dispose() {
    _question.dispose();
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  String? _labelError(int index, String? value) {
    final label = (value ?? '').trim();
    if (label.isEmpty) return 'Enter an option';
    if (label.runes.length > 100) return 'At most 100 characters';
    final earlier = [
      for (final option in _options.take(index)) _fold(option.label.text),
    ];
    return earlier.contains(_fold(label)) ? 'Already an option' : null;
  }

  Future<void> _save() async {
    clearFormError();
    if (!_formKey.currentState!.validate()) return;
    final closesAt = _closesAt;
    if (closesAt != null && !closesAt.isAfter(DateTime.now())) {
      setState(() {}); // shows the closing-time error below
      return;
    }
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(pollsControllerProvider.notifier)
          .create(
            widget.activityId,
            PollCreate(
              question: _question.text.trim(),
              allowMultiple: _allowMultiple,
              closesAt: ApiInstant.ofNullable(closesAt),
              options: [
                for (final option in _options)
                  PollOptionCreate(
                    label: option.label.text.trim(),
                    url: option.url.text.trim().isEmpty
                        ? null
                        : option.url.text.trim(),
                  ),
              ],
            ),
          );
      navigator.pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      showServerError(
        error,
        fields: const {'question', 'closes_at', 'options', 'allow_multiple'},
        messages: const {'limit_reached': 'This idea has 10 polls already.'},
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final closesAt = _closesAt;
    final pastClosing =
        closesAt != null && !closesAt.isAfter(DateTime.now()) && !_saving;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('New poll', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (formError case final message?) ...[
              FormMessageBanner(message: message),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _question,
              decoration: const InputDecoration(
                labelText: 'Question',
                hintText: 'e.g. Which movie?',
              ),
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              validator: Validators.required('a question', max: 200),
              forceErrorText: serverError('question'),
              onChanged: (_) => clearServerError('question'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow several choices'),
              subtitle: const Text("Can't be changed after the poll is made"),
              value: _allowMultiple,
              onChanged: (value) => setState(() => _allowMultiple = value),
            ),
            ClosingTimeField(
              value: closesAt,
              error:
                  serverError('closes_at') ??
                  (pastClosing ? 'Pick a time in the future' : null),
              onChanged: (value) {
                clearServerError('closes_at');
                setState(() => _closesAt = value);
              },
            ),
            const SizedBox(height: 16),
            Text('Options', style: Theme.of(context).textTheme.titleSmall),
            for (final (index, option) in _options.indexed)
              Row(
                key: ObjectKey(option),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: option.label,
                      decoration: InputDecoration(
                        labelText: 'Option ${index + 1}',
                      ),
                      maxLength: 100,
                      validator: (value) => _labelError(index, value),
                      forceErrorText: serverError('options.$index.label'),
                      onChanged: (_) => clearServerError('options.$index'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: option.url,
                      decoration: const InputDecoration(
                        labelText: 'Link (optional)',
                      ),
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      validator: _optionalUrl,
                      forceErrorText: serverError('options.$index.url'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove option ${index + 1}',
                    onPressed: _options.length <= minPollOptions
                        ? null
                        : () => setState(
                            () => _options.removeAt(index).dispose(),
                          ),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              ),
            if (_options.length < maxPollOptions)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(() => _options.add(_OptionDraft())),
                  icon: const Icon(Icons.add),
                  label: const Text('Add an option'),
                ),
              ),
            const SizedBox(height: 8),
            SubmitButton(label: 'Create poll', busy: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

/// Edits a poll's question and closing time; resolves to the new values or
/// null. The stored closing time may be sent back unchanged even if past.
Future<PollUpdate?> showEditPollDialog(BuildContext context, Poll poll) {
  return showDialog<PollUpdate>(
    context: context,
    builder: (context) => _EditPollDialog(poll: poll),
  );
}

class _EditPollDialog extends StatefulWidget {
  const new({required this.poll});

  final Poll poll;

  @override
  State<_EditPollDialog> createState() => _EditPollDialogState();
}

class _EditPollDialogState extends State<_EditPollDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _question = TextEditingController(text: widget.poll.question);
  late DateTime? _closesAt = widget.poll.closesAt;

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  bool get _closingIsValid {
    final closesAt = _closesAt;
    return closesAt == null ||
        closesAt == widget.poll.closesAt ||
        closesAt.isAfter(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit poll'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _question,
              decoration: const InputDecoration(labelText: 'Question'),
              maxLength: 200,
              validator: Validators.required('a question', max: 200),
            ),
            ClosingTimeField(
              value: _closesAt,
              error: _closingIsValid ? null : 'Pick a time in the future',
              onChanged: (value) => setState(() => _closesAt = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate() || !_closingIsValid) return;
            Navigator.of(context).pop(
              PollUpdate(
                question: _question.text.trim(),
                closesAt: ApiInstant.ofNullable(_closesAt),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Asks for a new option's label and optional link; null when cancelled.
Future<PollOptionCreate?> showAddOptionDialog(BuildContext context) {
  return showDialog<PollOptionCreate>(
    context: context,
    builder: (context) => const _AddOptionDialog(),
  );
}

class _AddOptionDialog extends StatefulWidget {
  const new();

  @override
  State<_AddOptionDialog> createState() => _AddOptionDialogState();
}

class _AddOptionDialogState extends State<_AddOptionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController();
  final _url = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add an option'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _label,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Option'),
              maxLength: 100,
              inputFormatters: [LengthLimitingTextInputFormatter(100)],
              validator: Validators.required('an option', max: 100),
            ),
            TextFormField(
              controller: _url,
              decoration: const InputDecoration(labelText: 'Link (optional)'),
              keyboardType: TextInputType.url,
              validator: _optionalUrl,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final url = _url.text.trim();
            Navigator.of(context).pop(
              PollOptionCreate(
                label: _label.text.trim(),
                url: url.isEmpty ? null : url,
              ),
            );
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
