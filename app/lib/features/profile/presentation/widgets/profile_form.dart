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
import 'package:friends/core/i18n/app_locale.dart';
import 'package:friends/core/widgets/form_widgets.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// Edits display name, birthday (month and day, optional year), timezone
/// and the app's language with `PUT /me`.
class ProfileForm extends ConsumerStatefulWidget {
  const new({required this.user, super.key});

  final Me user;

  @override
  ConsumerState<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<ProfileForm>
    with ServerErrorsMixin {
  static const _fields = {'display_name', 'birthday', 'timezone', 'locale'};

  /// January to December, in the app's language.
  static List<String> get _months => [
    for (final month in DateFormat.MMMM().dateSymbols.STANDALONEMONTHS)
      toBeginningOfSentenceCase(month),
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayName;
  late final TextEditingController _year;
  late final TextEditingController _timezone;
  int? _month;
  int? _day;

  /// One of [appLanguages], or null for the device's language.
  String? _locale;
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
    final language = user.locale?.split(RegExp('[-_]')).first.toLowerCase();
    _locale = appLanguages.containsKey(language) ? language : null;
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
      return context.l10n.birthdayBothOrNeither;
    }
    if (year.isEmpty) return null;
    final value = int.tryParse(year);
    if (_month == null) return context.l10n.birthdayNeedsDay;
    if (value == null || value < 1900 || value > DateTime.now().year) {
      return context.l10n.birthdayYearRange('${DateTime.now().year}');
    }
    if (_day! > _maxDay) return context.l10n.birthdayNoSuchDay('$value');
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
              locale: _locale,
              // PUT is the complete new state: keep what this form doesn't
              // edit.
              avatarUrl: widget.user.avatarUrl,
            ),
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.l10n.profileSaved)));
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
            decoration: InputDecoration(labelText: context.l10n.displayName),
            textCapitalization: TextCapitalization.words,
            validator: Validators.required(
              context.l10n.enterDisplayName,
              max: 50,
            ),
            forceErrorText: serverError('display_name'),
            onChanged: (_) => clearServerError('display_name'),
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.birthday,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.birthdayHelp,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<int?>(
                  initialValue: _month,
                  decoration: InputDecoration(
                    labelText: context.l10n.monthLabel,
                  ),
                  items: [
                    const DropdownMenuItem(child: Text('—')),
                    for (final (index, name) in _months.indexed)
                      DropdownMenuItem(value: index + 1, child: Text(name)),
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
                  decoration: InputDecoration(labelText: context.l10n.dayLabel),
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
                  decoration: InputDecoration(
                    labelText: context.l10n.yearLabel,
                    helperText: context.l10n.optional,
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
            decoration: InputDecoration(
              labelText: context.l10n.timezoneLabel,
              helperText: context.l10n.timezoneHelper,
            ),
            autocorrect: false,
            validator: Validators.required(context.l10n.enterTimezone, max: 64),
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
                label: Text(context.l10n.useDeviceTimezone(deviceZone)),
              ),
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            initialValue: _locale,
            decoration: InputDecoration(
              labelText: context.l10n.language,
              helperText: context.l10n.languageHelp,
              errorText: serverError('locale'),
            ),
            items: [
              DropdownMenuItem(child: Text(context.l10n.deviceLanguage)),
              // Each language in its own name.
              for (final MapEntry(key: tag, value: name)
                  in appLanguages.entries)
                DropdownMenuItem(value: tag, child: Text(name)),
            ],
            onChanged: (value) {
              clearServerError('locale');
              setState(() => _locale = value);
            },
          ),
          const SizedBox(height: 16),
          SubmitButton(
            label: context.l10n.saveProfile,
            busy: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
