import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/generated/models/birthday.dart';
import 'package:friends/core/api/generated/models/me.dart';
import 'package:friends/core/api/generated/models/me_update.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/device/device_info.dart';
import 'package:friends/core/forms/field_errors.dart';
import 'package:friends/core/forms/validators.dart';
import 'package:friends/core/widgets/form_widgets.dart';
import 'package:material_ui/material_ui.dart';

/// Edits display name, birthday (month and day, optional year) and timezone
/// with `PUT /me`.
class ProfileForm extends ConsumerStatefulWidget {
  const new({required this.user, super.key});

  final Me user;

  @override
  ConsumerState<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<ProfileForm>
    with ServerErrorsMixin {
  static const _fields = {'display_name', 'birthday', 'timezone'};
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayName;
  late final TextEditingController _year;
  late final TextEditingController _timezone;
  int? _month;
  int? _day;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _displayName = TextEditingController(text: user.displayName);
    _year = TextEditingController(text: user.birthday?.year?.toString());
    _timezone = TextEditingController(text: user.timezone);
    _month = user.birthday?.month;
    _day = user.birthday?.day;
  }

  @override
  void dispose() {
    _displayName.dispose();
    _year.dispose();
    _timezone.dispose();
    super.dispose();
  }

  int? get _yearValue => int.tryParse(_year.text.trim());

  /// Days the day picker offers for [_month]. February always has 29, since
  /// the year is optional; [_validateBirthday] rejects 29 February in a
  /// non-leap year.
  int get _daysInMonth {
    final month = _month;
    if (month == null) return 31;
    return DateTime(2000, month + 1, 0).day;
  }

  /// Days in [_month] of the entered year (or of a leap year).
  int get _maxDay {
    final month = _month;
    if (month == null) return 31;
    return DateTime(_yearValue ?? 2000, month + 1, 0).day;
  }

  String? _validateBirthday() {
    final year = _year.text.trim();
    if ((_month == null) != (_day == null)) {
      return 'Pick both a month and a day, or neither.';
    }
    if (year.isEmpty) return null;
    final value = int.tryParse(year);
    if (_month == null) return 'Pick a month and a day for the year.';
    if (value == null || value < 1900 || value > DateTime.now().year) {
      return 'Enter a year between 1900 and ${DateTime.now().year}.';
    }
    if (_day! > _maxDay) return 'That day does not exist in $value.';
    return null;
  }

  Future<void> _save() async {
    clearFormError();
    if (!_formKey.currentState!.validate()) return;
    final month = _month;
    final day = _day;
    setState(() => _saving = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .updateMe(
            MeUpdate(
              displayName: _displayName.text.trim(),
              timezone: _timezone.text.trim(),
              birthday: month == null || day == null
                  ? null
                  : Birthday(month: month, day: day, year: _yearValue),
              // PUT is the complete new state: keep what this form doesn't
              // edit.
              locale: widget.user.locale,
              avatarUrl: widget.user.avatarUrl,
            ),
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profile saved')));
      }
    } on ApiException catch (e) {
      if (mounted) showServerError(e, fields: _fields);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceZone = ref.watch(deviceTimezoneProvider).value;
    final birthdayError = serverError('birthday');
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (formError case final message?) ...[
            FormMessageBanner(message: message),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _displayName,
            decoration: const InputDecoration(labelText: 'Display name'),
            textCapitalization: TextCapitalization.words,
            validator: Validators.required('a display name', max: 50),
            forceErrorText: serverError('display_name'),
            onChanged: (_) => clearServerError('display_name'),
          ),
          const SizedBox(height: 16),
          Text('Birthday', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<int?>(
                  initialValue: _month,
                  decoration: const InputDecoration(labelText: 'Month'),
                  items: [
                    const DropdownMenuItem(child: Text('—')),
                    for (var m = 1; m <= 12; m++)
                      DropdownMenuItem(value: m, child: Text(_months[m - 1])),
                  ],
                  onChanged: (value) {
                    clearServerError('birthday');
                    setState(() {
                      _month = value;
                      if (value == null) _day = null;
                      if (_day != null && _day! > _daysInMonth) {
                        _day = _daysInMonth;
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<int?>(
                  // Rebuilt when the month changes, so the days fit it.
                  key: ValueKey('day-$_month'),
                  initialValue: _day,
                  decoration: const InputDecoration(labelText: 'Day'),
                  items: [
                    const DropdownMenuItem(child: Text('—')),
                    for (var d = 1; d <= _daysInMonth; d++)
                      DropdownMenuItem(value: d, child: Text('$d')),
                  ],
                  onChanged: (value) {
                    clearServerError('birthday');
                    setState(() => _day = value);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _year,
                  decoration: const InputDecoration(
                    labelText: 'Year',
                    helperText: 'Optional',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  onChanged: (_) {
                    clearServerError('birthday');
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
          // One error line for the three birthday fields.
          FormField<void>(
            validator: (_) => _validateBirthday(),
            forceErrorText: birthdayError,
            builder: (field) => field.hasError
                ? Padding(
                    padding: const EdgeInsets.only(top: 4, left: 12),
                    child: Text(
                      field.errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _timezone,
            decoration: const InputDecoration(
              labelText: 'Timezone',
              helperText: 'IANA name, e.g. Europe/Bucharest',
            ),
            autocorrect: false,
            validator: Validators.required('a timezone', max: 64),
            forceErrorText: serverError('timezone'),
            onChanged: (_) {
              clearServerError('timezone');
              setState(() {});
            },
          ),
          if (deviceZone != null && deviceZone != _timezone.text.trim())
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () {
                  clearServerError('timezone');
                  setState(() => _timezone.text = deviceZone);
                },
                icon: const Icon(Icons.my_location),
                label: Text('Use device timezone ($deviceZone)'),
              ),
            ),
          const SizedBox(height: 16),
          SubmitButton(label: 'Save profile', busy: _saving, onPressed: _save),
        ],
      ),
    );
  }
}
