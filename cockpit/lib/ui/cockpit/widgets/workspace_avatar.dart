import 'dart:io';

import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';

/// Avatar de um workspace. Por padrão é o quadrado colorido com a inicial do
/// nome; quando há [imagePath] (PNG/JPG escolhido em Workspace Settings), mostra
/// a imagem recortada no mesmo formato. Se o arquivo sumir/for ilegível, cai
/// num **placeholder de erro** (ícone de imagem quebrada) — nunca quebra a UI.
class WorkspaceAvatar extends StatelessWidget {
  const WorkspaceAvatar({
    super.key,
    required this.imagePath,
    required this.colorValue,
    required this.initial,
    this.size = 30,
    this.radius = 7,
  });

  /// Caminho absoluto da imagem ou `null` para o avatar de cor + inicial.
  final String? imagePath;
  final int colorValue;
  final String initial;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final path = imagePath;
    if (path != null && path.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(
          File(path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          // Arquivo movido/deletado/corrompido → placeholder de erro.
          errorBuilder: (context, _, _) => _box(
            context,
            child: Icon(
              Icons.broken_image_outlined,
              size: size * 0.5,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
    // Sem imagem: quadrado colorido com a inicial.
    return _box(
      context,
      child: Text(
        initial,
        style: context.typo.title.copyWith(
          fontSize: size * 0.43,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _box(BuildContext context, {required Widget child}) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color(colorValue),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}
