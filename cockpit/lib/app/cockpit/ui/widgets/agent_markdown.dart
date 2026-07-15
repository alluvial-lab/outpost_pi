import 'dart:async';

import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
// `gpt_markdown` is a Material package that styles headings, links, and code
// through Material's `Theme.of(context)` plus `GptMarkdownThemeData`. ShadcnApp
// supplies no Material theme, so the package falls back to light ThemeData with
// dark headings. Wrap only the markdown in a Material theme (the `m.` prefix)
// using Cockpit colors; the rest of the app remains shadcn.
import 'package:flutter/material.dart' as m;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Render an agent response as GFM and code with Cockpit styling.
///
/// Tolerates partial Markdown so streaming responses can render incrementally.
class AgentMarkdown extends StatelessWidget {
  const AgentMarkdown(this.data, {super.key});

  final String data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final brightness = Theme.of(context).brightness;
    // Give only gpt_markdown a Material theme using the Cockpit palette; without
    // it the package uses light ThemeData and dark headings. Transcript and file
    // viewer callers provide SelectionArea around scrolling so selection drags
    // can auto-scroll.
    final base = brightness == Brightness.dark
        ? m.ThemeData.dark()
        : m.ThemeData.light();
    return m.Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(
          surface: colors.panel,
          onSurface: colors.text,
          onSurfaceVariant: colors.text2,
          error: colors.error,
        ),
        extensions: [
          GptMarkdownThemeData(
            brightness: brightness,
            h1: typo.display.copyWith(color: colors.text, fontSize: 22),
            h2: typo.display.copyWith(color: colors.text, fontSize: 18),
            h3: typo.title.copyWith(color: colors.text, fontSize: 16),
            h4: typo.title.copyWith(color: colors.text, fontSize: 14.5),
            h5: typo.title.copyWith(color: colors.text, fontSize: 13.5),
            h6: typo.title.copyWith(color: colors.text2, fontSize: 12.5),
            linkColor: colors.accentText,
            linkHoverColor: colors.accent,
            hrLineColor: colors.border2,
            highlightColor: colors.panel3,
          ),
        ],
      ),
      child: GptMarkdown(
        data,
        style: typo.body.copyWith(color: colors.text),
        // Give inline `code` a subtle background and monospace text.
        highlightBuilder: (context, text, style) => Text(
          text,
          style: typo.mono.copyWith(
            fontSize: 12,
            color: colors.text,
            backgroundColor: colors.panel3,
          ),
        ),
        // Render fenced blocks as dark cards with language/copy headers.
        codeBuilder: (context, name, code, closed) =>
            _CodeBlock(language: name, code: code),
      ),
    );
  }
}

class _CodeBlock extends StatefulWidget {
  const _CodeBlock({required this.language, required this.code});

  final String language;
  final String code;

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  // Own a controller so the horizontal scrollbar can stay visible;
  // thumbVisibility requires sharing it with the scroll view.
  final ScrollController _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.language.isEmpty
                        ? 'code'
                        : widget.language.toUpperCase(),
                    style: typo.mono.copyWith(
                      fontSize: 10,
                      color: colors.text3,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                _CopyButton(code: widget.code),
              ],
            ),
          ),
          // Keep the horizontal scrollbar visible for code wider than the view.
          Scrollbar(
            controller: _horizontal,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Text(
                widget.code,
                style: typo.mono.copyWith(color: colors.text, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.code});
  final String code;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      tooltip: (context) => const TooltipContainer(child: Text('Copy code')),
      child: HoverTap(
        onTap: _copy,
        borderRadius: BorderRadius.circular(5),
        padding: const EdgeInsets.all(4),
        child: Icon(
          _copied ? Icons.check : Icons.copy,
          size: 14,
          color: _copied ? colors.ok : colors.text3,
        ),
      ),
    );
  }
}
