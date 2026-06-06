import 'dart:io';

import 'package:cockpit/domain/entities/file_view.dart';
import 'package:cockpit/ui/cockpit/widgets/agent_markdown.dart';
import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Corpo do viewer read-only: markdown (gpt_markdown), texto puro, ou imagem.
class FileViewer extends StatelessWidget {
  const FileViewer({super.key, required this.view});
  final FileView view;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.panel,
      child: switch (view) {
        FileViewMarkdown(:final text) => _Scroll(child: AgentMarkdown(text)),
        FileViewText(:final text) => _TextView(text: text),
        FileViewImage(:final path) => _ImageView(path: path),
        FileViewUnsupported() => Center(
          child: Text(
            'Não dá pra abrir esse arquivo.',
            style: context.typo.body.copyWith(color: colors.text3),
          ),
        ),
      },
    );
  }
}

class _Scroll extends StatelessWidget {
  const _Scroll({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: child,
    );
  }
}

/// Visualizador read-only de texto/código com **gutter de número de linha** à
/// esquerda (fixo na horizontal) e **scroll horizontal** pro conteúdo quando a
/// linha é longa. O texto segue selecionável; os números, não.
class _TextView extends StatefulWidget {
  const _TextView({required this.text});

  final String text;

  @override
  State<_TextView> createState() => _TextViewState();
}

class _TextViewState extends State<_TextView> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;

    const fontSize = 12.5;
    const lineHeight = 1.55;
    final codeStyle = typo.mono.copyWith(
      fontSize: fontSize,
      height: lineHeight,
      color: const Color(0xFFC9C9CF),
    );
    final numStyle = typo.mono.copyWith(
      fontSize: fontSize,
      height: lineHeight,
      color: colors.text4,
    );

    // Conta linhas pelos '\n' (arquivo sem newline final = última linha conta;
    // arquivo vazio = 1 linha). Mesma métrica do código → gutter alinha 1:1.
    final lineCount = '\n'.allMatches(widget.text).length + 1;

    return Scrollbar(
      controller: _vertical,
      child: SingleChildScrollView(
        controller: _vertical,
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Gutter — números à direita, fixo (não rola na horizontal).
            Padding(
              padding: const EdgeInsets.only(left: 14, right: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 1; i <= lineCount; i++)
                    Text('$i', style: numStyle),
                ],
              ),
            ),
            Container(width: 1, color: colors.border),
            // Código — rola na horizontal quando a linha estoura; selecionável.
            Expanded(
              child: Scrollbar(
                controller: _horizontal,
                child: SingleChildScrollView(
                  controller: _horizontal,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(left: 14, right: 16),
                  child: SelectableText(widget.text, style: codeStyle),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageView extends StatelessWidget {
  const _ImageView({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final file = File(path);
    final isSvg = path.toLowerCase().endsWith('.svg');
    return InteractiveViewer(
      maxScale: 8,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: isSvg
              ? SvgPicture.file(file, fit: BoxFit.contain)
              : Image.file(
                  file,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => Text(
                    'Não foi possível carregar a imagem.',
                    style: context.typo.body.copyWith(color: colors.text3),
                  ),
                ),
        ),
      ),
    );
  }
}
