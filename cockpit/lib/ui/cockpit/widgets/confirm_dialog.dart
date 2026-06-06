import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';

/// Dialog de confirmação genérico (tema do cockpit). Devolve `true` se confirmar.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirmar',
  String cancelLabel = 'Cancelar',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final colors = context.colors;
      return Dialog(
        backgroundColor: colors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: colors.border2),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.typo.title.copyWith(
                    fontSize: 15,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: context.typo.body.copyWith(
                    fontSize: 13.5,
                    color: colors.text2,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(cancelLabel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: danger ? colors.error : colors.accent,
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(confirmLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result ?? false;
}
