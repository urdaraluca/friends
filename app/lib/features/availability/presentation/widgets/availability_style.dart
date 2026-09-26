import 'package:friends/core/api/generated/export.dart';
import 'package:material_ui/material_ui.dart';

/// The colour of an answer.
Color statusColor(AvailabilityStatus status) => switch (status) {
  AvailabilityStatus.free => const Color(0xFF43A047),
  AvailabilityStatus.maybe => const Color(0xFFFFB300),
  AvailabilityStatus.busy => const Color(0xFFE53935),
  AvailabilityStatus.$unknown => const Color(0xFF9E9E9E),
};

/// "Free", "Maybe", "Busy", or "Not set" for no answer.
String statusLabel(AvailabilityStatus? status) => switch (status) {
  AvailabilityStatus.free => 'Free',
  AvailabilityStatus.maybe => 'Maybe',
  AvailabilityStatus.busy => 'Busy',
  null || AvailabilityStatus.$unknown => 'Not set',
};

/// "All day", "Morning", "Afternoon" or "Evening".
String slotLabel(AvailabilitySlot slot) => switch (slot) {
  AvailabilitySlot.allDay || AvailabilitySlot.$unknown => 'All day',
  AvailabilitySlot.morning => 'Morning',
  AvailabilitySlot.afternoon => 'Afternoon',
  AvailabilitySlot.evening => 'Evening',
};

/// Black or white, whichever reads better on [background].
Color onColor(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
    ? Colors.white
    : Colors.black87;

/// One chip per slot, [selected] highlighted.
class SlotChips extends StatelessWidget {
  const new({
    required this.selected,
    required this.onSelected,
    this.allDayLabel = 'All day',
    super.key,
  });

  final AvailabilitySlot selected;
  final ValueChanged<AvailabilitySlot> onSelected;
  final String allDayLabel;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        for (final slot in AvailabilitySlot.$valuesDefined)
          ChoiceChip(
            label: Text(
              slot == AvailabilitySlot.allDay ? allDayLabel : slotLabel(slot),
            ),
            selected: slot == selected,
            onSelected: (_) => onSelected(slot),
          ),
      ],
    );
  }
}
