import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/links/open_link.dart';
import 'package:friends/features/backlog/domain/field_values.dart';
import 'package:material_ui/material_ui.dart';

/// An activity's custom-field values in the order of the category's
/// effective field definitions, each rendered by its type: a rating with a
/// star, a link to tap, a choice as a chip, text and numbers as text.
///
/// The server already filtered the values (contract section 6.4), so only
/// keys of [fieldDefs] appear; empty fields are left out.
class AttributesView extends ConsumerWidget {
  const new({required this.fieldDefs, required this.attributes, super.key});

  final List<FieldDef> fieldDefs;

  /// `Activity.attributes`: key → string or number.
  final Object? attributes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final values = attributes is Map
        ? attributes! as Map<Object?, Object?>
        : const <Object?, Object?>{};
    final shown = [
      for (final def in fieldDefs)
        if (values[def.key] case final value? when '$value'.isNotEmpty)
          (def, value),
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (def, value) in shown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    def.label,
                    style: textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _value(context, ref, def, value)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _value(
    BuildContext context,
    WidgetRef ref,
    FieldDef def,
    Object value,
  ) {
    final text = FieldValues.toText(value);
    switch (def.type) {
      case FieldType.rating:
        final max = FieldValues.maxOf(def);
        return Row(
          children: [
            const Icon(Icons.star, size: 18, color: Color(0xFFF5B301)),
            const SizedBox(width: 4),
            Text(max == null ? text : '$text / ${FieldValues.toText(max)}'),
          ],
        );
      case FieldType.url:
        final uri = Uri.tryParse(text);
        if (uri == null) return Text(text);
        return InkWell(
          onTap: () => openLink(context, ref, uri),
          child: Text(
            uri.host.isEmpty ? text : '${uri.host}${uri.path}',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        );
      case FieldType.select:
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: Chip(
            label: Text(text),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
      case FieldType.text ||
          FieldType.longText ||
          FieldType.number ||
          FieldType.year ||
          FieldType.$unknown:
        return SelectableText(text);
    }
  }
}
