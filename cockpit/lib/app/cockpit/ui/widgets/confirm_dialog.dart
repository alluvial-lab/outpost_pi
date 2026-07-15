import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Dim modal backgrounds because shadcn dialogs use a transparent barrier.
const Color _barrier = Color(0x99000000);

/// Show a cockpit-themed informational dialog with one acknowledgment action.
Future<void> showInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
  String okLabel = 'Got it',
}) {
  return showDialog<void>(
    context: context,
    barrierColor: _barrier,
    builder: (context) {
      final colors = context.colors;
      return AlertDialog(
        title: Text(
          title,
          style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Text(
            message,
            style: context.typo.body.copyWith(
              fontSize: 13.5,
              color: colors.text2,
            ),
          ),
        ),
        actions: [
          PrimaryButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(okLabel),
          ),
        ],
      );
    },
  );
}

/// Represent the user's choice when closing a tab with unsaved changes.
enum CloseDirtyChoice { cancel, dontSave, save }

/// Ask how to handle unsaved edits before closing a file tab.
///
/// Dismissing the dialog is treated as [CloseDirtyChoice.cancel].
Future<CloseDirtyChoice> showCloseDirtyDialog(
  BuildContext context, {
  required String fileName,
}) async {
  final result = await showDialog<CloseDirtyChoice>(
    context: context,
    barrierColor: _barrier,
    builder: (context) {
      final colors = context.colors;
      return AlertDialog(
        title: Text(
          'Unsaved changes',
          style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Text(
            '“$fileName” has unsaved changes. Save them before closing?',
            style: context.typo.body.copyWith(
              fontSize: 13.5,
              color: colors.text2,
            ),
          ),
        ),
        actions: [
          DestructiveButton(
            onPressed: () =>
                Navigator.of(context).pop(CloseDirtyChoice.dontSave),
            child: const Text('Don\'t save'),
          ),
          OutlineButton(
            onPressed: () => Navigator.of(context).pop(CloseDirtyChoice.cancel),
            child: const Text('Cancel'),
          ),
          PrimaryButton(
            onPressed: () => Navigator.of(context).pop(CloseDirtyChoice.save),
            child: const Text('Save & close'),
          ),
        ],
      );
    },
  );
  return result ?? CloseDirtyChoice.cancel;
}

/// Show a cockpit-themed confirmation dialog.
///
/// Returns `true` only when the confirm action is selected.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: _barrier,
    builder: (context) {
      final colors = context.colors;
      return AlertDialog(
        title: Text(
          title,
          style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Text(
            message,
            style: context.typo.body.copyWith(
              fontSize: 13.5,
              color: colors.text2,
            ),
          ),
        ),
        actions: [
          OutlineButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel),
          ),
          if (danger)
            DestructiveButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            )
          else
            PrimaryButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
        ],
      );
    },
  );
  return result ?? false;
}
