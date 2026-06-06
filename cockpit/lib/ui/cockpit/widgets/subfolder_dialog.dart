import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';

/// Pergunta em qual pasta dentro do projeto o agente vai atuar. Devolve o
/// caminho **relativo** escolhido (`''` = raiz do projeto), ou `null` se cancelar.
Future<String?> showSubfolderDialog(
  BuildContext context, {
  required String projectName,
  required List<String> subfolders,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _SubfolderDialog(
      projectName: projectName,
      subfolders: subfolders,
    ),
  );
}

class _SubfolderDialog extends StatelessWidget {
  const _SubfolderDialog({
    required this.projectName,
    required this.subfolders,
  });

  final String projectName;
  final List<String> subfolders;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.border2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
              child: Text(
                'Onde o agente vai atuar?',
                style: context.typo.title.copyWith(
                  fontSize: 15,
                  color: colors.text,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Text(
                'Pasta dentro de $projectName',
                style: context.typo.label.copyWith(color: colors.text3),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  _FolderRow(
                    icon: Icons.home_outlined,
                    label: 'Raiz do projeto',
                    sublabel: projectName,
                    onTap: () => Navigator.of(context).pop(''),
                  ),
                  for (final folder in subfolders)
                    _FolderRow(
                      icon: Icons.folder_outlined,
                      label: folder,
                      onTap: () => Navigator.of(context).pop(folder),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.sublabel,
  });

  final IconData icon;
  final String label;
  final String? sublabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 16, color: colors.text3),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.body.copyWith(
                    fontSize: 13.5,
                    color: colors.text,
                  ),
                ),
              ),
              if (sublabel != null)
                Text(
                  sublabel!,
                  style: context.typo.mono.copyWith(
                    fontSize: 11,
                    color: colors.text4,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
