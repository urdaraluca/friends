import 'package:material_ui/material_ui.dart';

/// Tells the user that someone else saved first (`409 version_conflict`,
/// contract section 1.7). The only way on is "Reload": there is no
/// "Overwrite". Resolves once the dialog is closed.
Future<void> showVersionConflictDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Someone else saved first'),
      content: const Text(
        'This was changed while you were editing. Reload to see the latest '
        'version, then make your changes again.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Reload'),
        ),
      ],
    ),
  );
}
