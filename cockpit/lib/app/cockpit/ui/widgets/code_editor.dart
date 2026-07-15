import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:flutter/material.dart'
    show
        Icon,
        Icons,
        Scrollbar,
        ScrollbarOrientation,
        TextField,
        InputDecoration,
        InputBorder,
        TextInputType,
        Tooltip;
import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/widgets.dart';

/// Edit code beside a fixed line-number gutter without wrapping long lines.
///
/// An outer vertical scroll contains a fixed gutter, divider, and horizontally
/// scrolling field. The field grows to full content height without internal
/// scrolling so gutter rows stay aligned. [FileViewer] owns dirty state and save
/// behavior by listening to [controller].
class CodeEditor extends StatefulWidget {
  const CodeEditor({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  final CodeEditingController controller;
  final FocusNode focusNode;

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();

  @override
  void initState() {
    super.initState();
    // Recount gutter rows after edits that change the number of newlines.
    widget.controller.addListener(_onChanged);
  }

  int _lineCount = 1;
  List<LspDiagnostic> _lastDiag = const <LspDiagnostic>[];

  // Show diagnostics at line rather than column granularity when hovering.
  double _lineHeight =
      18; // Pixels per line; recalculated in build via TextPainter.
  static const double _padTop = 14; // SingleChildScrollView vertical padding.
  int? _hoverLine;
  List<String> _hoverMsgs = const <String>[];
  double _hoverDx = 0;

  void _onHover(PointerHoverEvent event) {
    final scroll = _vertical.hasClients ? _vertical.offset : 0.0;
    final contentY = event.localPosition.dy - _padTop + scroll;
    if (contentY < 0 || _lineHeight <= 0) return _clearHover();
    final line = (contentY ~/ _lineHeight); // base 0
    if (line == _hoverLine) return; // No work when still on the same line.
    final msgs = widget.controller.messagesForLine(line);
    setState(() {
      _hoverLine = line;
      _hoverMsgs = msgs;
      _hoverDx = event.localPosition.dx;
    });
  }

  void _clearHover() {
    if (_hoverLine == null && _hoverMsgs.isEmpty) return;
    setState(() {
      _hoverLine = null;
      _hoverMsgs = const <String>[];
    });
  }

  void _onChanged() {
    final n = '\n'.allMatches(widget.controller.text).length + 1;
    final diag = widget.controller.diagnostics;
    // Rebuild the gutter when line count or diagnostics change. The text field
    // repaints itself through buildTextSpan, while the gutter requires setState.
    if ((n != _lineCount || !identical(diag, _lastDiag)) && mounted) {
      setState(() {
        _lineCount = n;
        _lastDiag = diag;
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  /// Reserve a fixed severity-icon slot even when no diagnostic exists.
  ///
  /// This prevents the gutter width from shifting code as errors appear or vanish.
  static const double _iconSlot = 16;

  /// Build one gutter row from a fixed severity slot and line number.
  ///
  /// A 12px icon fits within text line height to preserve one-to-one alignment.
  Widget _gutterLine(int oneBased, TextStyle numStyle) {
    final severity = widget.controller.severityForLine(oneBased - 1);
    final Widget slot;
    if (severity == null) {
      slot = const SizedBox(width: _iconSlot);
    } else {
      final messages = widget.controller.messagesForLine(oneBased - 1);
      slot = SizedBox(
        width: _iconSlot,
        child: Tooltip(
          message: messages.join('\n'),
          child: Icon(
            _severityIcon(severity),
            size: 12,
            color: SyntaxColors.diagnosticColor(severity),
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        slot,
        Text('$oneBased', style: numStyle),
      ],
    );
  }

  IconData _severityIcon(LspSeverity severity) => switch (severity) {
    LspSeverity.error => Icons.error,
    LspSeverity.warning => Icons.warning_amber_rounded,
    LspSeverity.info => Icons.info_outline,
    LspSeverity.hint => Icons.lightbulb_outline,
  };

  @override
  Widget build(BuildContext context) {
    final typo = context.typo;
    final syntax = context.syntax;
    final codeStyle = typo.mono.copyWith(color: syntax.base);
    _lineCount = '\n'.allMatches(widget.controller.text).length + 1;

    // Map mouse position to a line index using line height in pixels.
    final lineProbe = TextPainter(
      text: TextSpan(text: 'X', style: codeStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    _lineHeight = lineProbe.preferredLineHeight;

    // Focus the field when clicking gutter, padding, or space below the last
    // line. TextField wins its own gesture arena to position the cursor; other
    // clicks fall through here. Translucent behavior preserves field taps.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (!widget.focusNode.hasFocus) widget.focusNode.requestFocus();
      },
      child: ColoredBox(
        color: syntax.background,
        child: MouseRegion(
          onHover: _onHover,
          onExit: (_) => _clearHover(),
          child: LayoutBuilder(
            builder: (context, viewport) => Stack(
              children: [
                _editorScroll(),
                if (_hoverMsgs.isNotEmpty && _hoverLine != null)
                  _hoverOverlay(context, viewport.maxWidth),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Show hovered-line diagnostic messages beneath that line.
  ///
  /// Coordinates are relative to the Stack's viewport origin.
  Widget _hoverOverlay(BuildContext context, double maxWidth) {
    final colors = context.colors;
    final scroll = _vertical.hasClients ? _vertical.offset : 0.0;
    final lineTop = _padTop + (_hoverLine! * _lineHeight) - scroll;
    const tipWidth = 360.0;
    final left = _hoverDx.clamp(
      8.0,
      (maxWidth - tipWidth - 8).clamp(8.0, maxWidth),
    );
    return Positioned(
      left: left,
      top: lineTop + _lineHeight + 2,
      child: IgnorePointer(
        child: Container(
          constraints: const BoxConstraints(maxWidth: tipWidth),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: colors.panel2,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: colors.border),
          ),
          child: Text(
            _hoverMsgs.join('\n'),
            style: context.typo.label.copyWith(color: colors.text),
          ),
        ),
      ),
    );
  }

  Widget _editorScroll() {
    final syntax = context.syntax;
    final typo = context.typo;
    final codeStyle = typo.mono.copyWith(color: syntax.base);
    final numStyle = typo.mono.copyWith(
      color: syntax.base.withValues(alpha: 0.4),
    );
    final lineCount = _lineCount;
    return Scrollbar(
      controller: _horizontal,
      thumbVisibility: true,
      scrollbarOrientation: ScrollbarOrientation.bottom,
      notificationPredicate: (n) => n.depth == 1,
      child: Scrollbar(
        controller: _vertical,
        child: SingleChildScrollView(
          controller: _vertical,
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 14, right: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 1; i <= lineCount; i++)
                      _gutterLine(i, numStyle),
                  ],
                ),
              ),
              Container(width: 1, color: syntax.base.withValues(alpha: 0.15)),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Keep minimum width at the viewport minus horizontal padding;
                    // otherwise IntrinsicWidth collapses an empty new file and
                    // leaves no area to click or type.
                    final minWidth = (constraints.maxWidth - 30).clamp(
                      0.0,
                      double.infinity,
                    );
                    return SingleChildScrollView(
                      controller: _horizontal,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(left: 14, right: 16),
                      // Use TextField rather than raw EditableText for desktop
                      // selection gestures: drag, double-click, and Cmd+A.
                      // Controller buildTextSpan supplies highlighting; decoration
                      // removes border and background.
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: minWidth),
                        child: IntrinsicWidth(
                          child: TextField(
                            controller: widget.controller,
                            focusNode: widget.focusNode,
                            style: codeStyle,
                            cursorColor: syntax.base,
                            maxLines: null,
                            minLines: null,
                            // Let the outer container own vertical scrolling while
                            // the field grows to full height so gutter rows align.
                            expands: false,
                            keyboardType: TextInputType.multiline,
                            decoration: const InputDecoration(
                              isCollapsed: true,
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
