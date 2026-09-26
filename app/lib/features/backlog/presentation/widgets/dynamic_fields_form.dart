import 'package:flutter/services.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/features/backlog/domain/field_values.dart';
import 'package:material_ui/material_ui.dart';

/// The inputs for a category's custom fields (contract section 6): one per
/// effective field definition, in their order.
///
/// | Type | Input |
/// |---|---|
/// | `text` | single line (≤200) |
/// | `long_text` | multiline (≤5000) |
/// | `number` | numeric, within min/max |
/// | `rating` | a slider in 0.1 steps within min..max (default 0–10) |
/// | `url` | URL input |
/// | `select` | dropdown of the options |
/// | `year` | numeric, 1800–2200 |
///
/// [values] holds each field's text; an empty text clears the key
/// (`FieldValues.parse`). [serverError] gives the 422 `invalid_attributes`
/// message for a key (`attributes.<key>`).
class DynamicFieldsForm extends StatelessWidget {
  const new({
    required this.fieldDefs,
    required this.values,
    required this.onChanged,
    this.serverError,
    super.key,
  });

  final List<FieldDef> fieldDefs;
  final Map<String, String> values;
  final void Function(String key, String text) onChanged;
  final String? Function(String key)? serverError;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final def in fieldDefs)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _FieldInput(
              key: ValueKey('attribute-${def.key}-${def.type.name}'),
              def: def,
              text: values[def.key] ?? '',
              error: serverError?.call(def.key),
              onChanged: (text) => onChanged(def.key, text),
            ),
          ),
      ],
    );
  }
}

class _FieldInput extends StatelessWidget {
  const new({
    required this.def,
    required this.text,
    required this.error,
    required this.onChanged,
    super.key,
  });

  final FieldDef def;
  final String text;
  final String? error;
  final ValueChanged<String> onChanged;

  String? _validate(String? value) => FieldValues.validate(def, value);

  @override
  Widget build(BuildContext context) {
    switch (def.type) {
      case FieldType.select:
        final options = def.options ?? const [];
        return DropdownButtonFormField<String>(
          initialValue: options.contains(text) ? text : '',
          decoration: InputDecoration(labelText: def.label),
          forceErrorText: error,
          items: [
            const DropdownMenuItem(value: '', child: Text('—')),
            for (final option in options)
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: (value) => onChanged(value ?? ''),
        );
      case FieldType.rating:
        return _RatingInput(
          def: def,
          text: text,
          error: error,
          onChanged: onChanged,
        );
      case FieldType.longText:
        return TextFormField(
          initialValue: text,
          decoration: InputDecoration(labelText: def.label),
          minLines: 2,
          maxLines: 6,
          maxLength: FieldValues.maxLongText,
          validator: _validate,
          forceErrorText: error,
          onChanged: onChanged,
        );
      case FieldType.number || FieldType.year:
        final integer = def.type == FieldType.year;
        final min = FieldValues.minOf(def);
        final max = FieldValues.maxOf(def);
        return TextFormField(
          initialValue: text,
          decoration: InputDecoration(
            labelText: def.label,
            helperText: min != null && max != null
                ? '${FieldValues.toText(min)}–${FieldValues.toText(max)}'
                : null,
          ),
          keyboardType: TextInputType.numberWithOptions(
            decimal: !integer,
            signed: !integer && (min == null || min < 0),
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              RegExp(integer ? '[0-9]' : r'[0-9.,\-]'),
            ),
          ],
          validator: _validate,
          forceErrorText: error,
          onChanged: onChanged,
        );
      case FieldType.url:
        return TextFormField(
          initialValue: text,
          decoration: InputDecoration(
            labelText: def.label,
            hintText: 'https://…',
          ),
          keyboardType: TextInputType.url,
          autocorrect: false,
          validator: _validate,
          forceErrorText: error,
          onChanged: onChanged,
        );
      case FieldType.text || FieldType.$unknown:
        return TextFormField(
          initialValue: text,
          decoration: InputDecoration(labelText: def.label),
          maxLength: FieldValues.maxText,
          validator: _validate,
          forceErrorText: error,
          onChanged: onChanged,
        );
    }
  }
}

/// A rating: "Rate it" while empty, then a slider in 0.1 steps with a
/// button to clear it.
class _RatingInput extends StatelessWidget {
  const new({
    required this.def,
    required this.text,
    required this.error,
    required this.onChanged,
  });

  final FieldDef def;
  final String text;
  final String? error;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final min = (FieldValues.minOf(def) ?? FieldValues.defaultRatingMin)
        .toDouble();
    final max = (FieldValues.maxOf(def) ?? FieldValues.defaultRatingMax)
        .toDouble();
    final value = double.tryParse(text);
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: def.label,
        border: InputBorder.none,
        errorText: error,
        contentPadding: EdgeInsets.zero,
      ),
      child: value == null
          ? Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () =>
                    onChanged(_format(((min + max) / 2 * 10).round() / 10)),
                icon: const Icon(Icons.star_outline),
                label: const Text('Rate it'),
              ),
            )
          : Row(
              children: [
                const Icon(Icons.star, color: Color(0xFFF5B301)),
                Expanded(
                  child: Slider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    divisions: ((max - min) * 10).round().clamp(1, 1000),
                    label: _format(value),
                    onChanged: (v) => onChanged(_format((v * 10).round() / 10)),
                  ),
                ),
                Text(_format(value), style: textTheme.titleMedium),
                IconButton(
                  tooltip: 'Clear ${def.label}',
                  icon: Icon(Icons.clear, color: colors.onSurfaceVariant),
                  onPressed: () => onChanged(''),
                ),
              ],
            ),
    );
  }

  static String _format(num value) => FieldValues.toText(value);
}
