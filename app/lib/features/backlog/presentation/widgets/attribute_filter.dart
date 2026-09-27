import 'package:flutter/services.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// The most attribute filters a request may combine (contract section 8.7).
const maxAttributeFilters = 5;

/// Field types that can be filtered on.
bool isFilterable(FieldDef def) => switch (def.type) {
  FieldType.number || FieldType.rating || FieldType.year => true,
  FieldType.select || FieldType.text || FieldType.longText => true,
  FieldType.url || FieldType.$unknown => false,
};

/// [filter] as the `attr` query value: `key:op:value`.
String attrParam(AttributeFilter filter) =>
    '${filter.key}:${filter.op.json}:${filter.value}';

/// "IMDb rating ≥ 7.5", "Genre: Comedy", "Notes contains ‘pizza’".
String attributeFilterLabel(AttributeFilter filter, List<FieldDef> defs) {
  final label =
      defs.where((d) => d.key == filter.key).firstOrNull?.label ?? filter.key;
  return switch (filter.op) {
    AttributeOp.gte => '$label ≥ ${filter.value}',
    AttributeOp.lte => '$label ≤ ${filter.value}',
    AttributeOp.contains => currentL10n.attributeContains(label, filter.value),
    AttributeOp.eq || AttributeOp.$unknown => '$label: ${filter.value}',
  };
}

/// A chip for filtering on the custom fields of the selected category
/// ([fieldDefs], its effective ones). Nothing when none can be filtered on.
class AttributeFilterChip extends StatelessWidget {
  const new({
    required this.fieldDefs,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final List<FieldDef> fieldDefs;
  final List<AttributeFilter> value;
  final ValueChanged<List<AttributeFilter>> onChanged;

  @override
  Widget build(BuildContext context) {
    final defs = fieldDefs.where(isFilterable).toList();
    if (defs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InputChip(
        avatar: const Icon(Icons.tune, size: 18),
        label: Text(
          value.isEmpty
              ? context.l10n.fieldsLabel
              : value.map((f) => attributeFilterLabel(f, defs)).join(' · '),
        ),
        selected: value.isNotEmpty,
        showCheckmark: false,
        onPressed: () async {
          final result = await showDialog<List<AttributeFilter>>(
            context: context,
            builder: (context) =>
                AttributeFilterDialog(fieldDefs: defs, value: value),
          );
          if (result != null) onChanged(result);
        },
        onDeleted: value.isEmpty ? null : () => onChanged(const []),
      ),
    );
  }
}

/// One input per filterable field: a range for numbers, a choice for a
/// select, "contains" for text. Pops the filters, at most
/// [maxAttributeFilters].
class AttributeFilterDialog extends StatefulWidget {
  const new({required this.fieldDefs, required this.value, super.key});

  final List<FieldDef> fieldDefs;
  final List<AttributeFilter> value;

  @override
  State<AttributeFilterDialog> createState() => _AttributeFilterDialogState();
}

class _AttributeFilterDialogState extends State<AttributeFilterDialog> {
  final _controllers = <String, TextEditingController>{};
  final _choices = <String, String?>{};
  String? _error;

  String? _initial(String key, AttributeOp op) =>
      widget.value.where((f) => f.key == key && f.op == op).firstOrNull?.value;

  TextEditingController _controller(String key, AttributeOp op) =>
      _controllers.putIfAbsent(
        '$key|${op.json}',
        () => TextEditingController(text: _initial(key, op) ?? ''),
      );

  @override
  void initState() {
    super.initState();
    for (final def in widget.fieldDefs) {
      if (def.type == FieldType.select) {
        _choices[def.key] = _initial(def.key, AttributeOp.eq);
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool _numeric(FieldDef def) =>
      def.type == FieldType.number ||
      def.type == FieldType.rating ||
      def.type == FieldType.year;

  List<AttributeFilter>? _collect() {
    final filters = <AttributeFilter>[];
    for (final def in widget.fieldDefs) {
      if (_numeric(def)) {
        for (final op in [AttributeOp.gte, AttributeOp.lte]) {
          final text = _controller(
            def.key,
            op,
          ).text.trim().replaceAll(',', '.');
          if (text.isEmpty) continue;
          if (num.tryParse(text) == null) {
            setState(() => _error = context.l10n.fieldEnterNumber(def.label));
            return null;
          }
          filters.add(AttributeFilter(key: def.key, op: op, value: text));
        }
      } else if (def.type == FieldType.select) {
        final choice = _choices[def.key];
        if (choice != null) {
          filters.add(
            AttributeFilter(key: def.key, op: AttributeOp.eq, value: choice),
          );
        }
      } else {
        final text = _controller(def.key, AttributeOp.contains).text.trim();
        if (text.isNotEmpty) {
          filters.add(
            AttributeFilter(
              key: def.key,
              op: AttributeOp.contains,
              value: text,
            ),
          );
        }
      }
    }
    if (filters.length > maxAttributeFilters) {
      setState(
        () => _error = context.l10n.tooManyFieldFilters(maxAttributeFilters),
      );
      return null;
    }
    return filters;
  }

  @override
  Widget build(BuildContext context) {
    final numberFormat = [
      FilteringTextInputFormatter.allow(RegExp('[0-9.,-]')),
      LengthLimitingTextInputFormatter(12),
    ];
    return AlertDialog(
      title: Text(context.l10n.filterByFields),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final def in widget.fieldDefs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: switch (def.type) {
                    _ when _numeric(def) => Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller(def.key, AttributeOp.gte),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            inputFormatters: numberFormat,
                            decoration: InputDecoration(
                              labelText: context.l10n.fieldAtLeast(def.label),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _controller(def.key, AttributeOp.lte),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            inputFormatters: numberFormat,
                            decoration: InputDecoration(
                              labelText: context.l10n.atMostLower,
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    FieldType.select => DropdownButtonFormField<String?>(
                      initialValue: _choices[def.key],
                      decoration: InputDecoration(
                        labelText: def.label,
                        isDense: true,
                      ),
                      items: [
                        DropdownMenuItem(child: Text(context.l10n.anyValue)),
                        for (final option in def.options ?? const <String>[])
                          DropdownMenuItem(value: option, child: Text(option)),
                      ],
                      onChanged: (choice) =>
                          setState(() => _choices[def.key] = choice),
                    ),
                    _ => TextField(
                      controller: _controller(def.key, AttributeOp.contains),
                      inputFormatters: [LengthLimitingTextInputFormatter(100)],
                      decoration: InputDecoration(
                        labelText: context.l10n.fieldContains(def.label),
                        isDense: true,
                      ),
                    ),
                  },
                ),
              if (_error case final error?)
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(const <AttributeFilter>[]),
          child: Text(context.l10n.clear),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            final filters = _collect();
            if (filters != null) Navigator.of(context).pop(filters);
          },
          child: Text(context.l10n.apply),
        ),
      ],
    );
  }
}
