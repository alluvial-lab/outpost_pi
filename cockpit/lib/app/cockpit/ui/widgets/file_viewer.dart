import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/agent_markdown.dart';
import 'package:cockpit/app/cockpit/ui/widgets/code_editor.dart';
import 'package:cockpit/app/core/data/lsp/lsp_command.dart';
import 'package:cockpit/app/core/data/lsp/lsp_launchers.dart';
import 'package:cockpit/app/core/data/lsp/lsp_text_edit.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/ui/async_action.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:cockpit/app/core/ui/widgets/code_highlight.dart';
import 'package:cockpit/app/cockpit/ui/widgets/media_view.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:flutter_modular/flutter_modular.dart';
// Material's SelectionArea wraps Markdown scrolling for selection auto-scroll.
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Format a content-free diagnostic for a formatter reload failure.
///
/// The error class distinguishes failure families without retaining paths,
/// messages, or stack traces from filesystem exceptions.
@visibleForTesting
String fileViewerReloadFailureDiagnostic(Object error) =>
    '[file-viewer] reload-from-disk failed (${error.runtimeType})';

/// Present Markdown, text, images, or audio/video within a file tab.
///
/// Text and Markdown can switch between rendered/read-only and guttered editing.
/// Cmd+S or the toolbar saves through [onSave], while a dirty dot marks unsaved
/// changes. Media, images, and unsupported types remain read-only.
class FileViewer extends StatefulWidget {
  const FileViewer({
    super.key,
    required this.session,
    required this.onSave,
    this.active = true,
    this.focused = true,
  });

  final FileViewerSession session;

  /// Persist edited content and report whether the save succeeded.
  final Future<bool> Function(String content) onSave;

  /// Indicate whether this tab is visible.
  ///
  /// Audio/video pauses when this becomes false; non-media types ignore it.
  final bool active;

  /// Indicate that this tab is active in the focused pane.
  ///
  /// The editor then receives keyboard focus automatically.
  final bool focused;

  @override
  State<FileViewer> createState() => _FileViewerState();
}

class _FileViewerState extends State<FileViewer> {
  /// Track text editing or Markdown source mode; false means preview.
  bool _editing = false;
  bool _dirty = false;
  bool _saving = false;
  String _baseline = '';
  String? _lastObservedPath;

  CodeEditingController? _ctrl;
  final _focus = FocusNode();

  /// Own the cached LSP ViewModel, diagnostic subscription, and didChange debounce.
  ///
  /// `_diagnostics` mirrors the latest document batch for both the editor and
  /// read-only viewer.
  CockpitViewModel? _vm;
  StreamSubscription<LspDiagnosticsBatch>? _diagSub;
  Timer? _lspDebounce;
  List<LspDiagnostic> _diagnostics = const <LspDiagnostic>[];

  /// Return current editable text, or `null` for a non-editable type.
  String? get _editableText => switch (widget.session.view) {
    FileViewText(:final text) => text,
    FileViewMarkdown(:final text) => text,
    FileViewSvg(:final text) => text,
    _ => null,
  };

  /// Resolve highlighting language from text extension, Markdown, or SVG XML.
  String? get _language => switch (widget.session.view) {
    FileViewText(:final language) => language,
    FileViewMarkdown() => 'markdown',
    FileViewSvg() => 'xml',
    _ => null,
  };

  /// Indicate whether Markdown or SVG offers preview in addition to source.
  ///
  /// Other text/code enters editing directly without a Preview/Source toggle.
  bool get _hasPreview =>
      widget.session.view is FileViewMarkdown ||
      widget.session.view is FileViewSvg;

  @override
  void initState() {
    super.initState();
    _lastObservedPath = widget.session.path;
    final text = _editableText;
    if (text != null) {
      _baseline = text;
      _ctrl = CodeEditingController(text: text, language: _language)
        ..addListener(_onCtrlChanged);
      // Expose buffer save to the session for "Save and close"; clear on dispose.
      widget.session.saveDraft = _save;
      _startLsp(text);
    }
    // Focus the editor when a newly opened tab starts focused.
    _focusEditorIfActive();
  }

  /// Open the document in LSP and subscribe to its diagnostics.
  ///
  /// No-ops for languages without a server because the pool degrades gracefully.
  void _startLsp(String text) {
    final vm = context.read<CockpitViewModel>();
    _vm = vm;
    final path = widget.session.path;
    final uri = Uri.file(path).toString();
    unawaited(vm.lspOpenDocument(path, text, widget.session.projectId));
    _diagSub = vm.lspDiagnostics.listen((batch) {
      if (batch.uri != uri || !mounted) return;
      setState(() => _diagnostics = batch.diagnostics);
      _ctrl?.diagnostics = batch.diagnostics;
    });
  }

  @override
  void didUpdateWidget(FileViewer old) {
    super.didUpdateWidget(old);

    // Force a full rebuild when a reused preview changes path.
    if (widget.session.path != _lastObservedPath) {
      final oldPath = _lastObservedPath;
      _lastObservedPath = widget.session.path;
      _cancelLspDebounce();
      _editing = false;
      _dirty = false;
      _baseline = '';
      _ctrl?.removeListener(_onCtrlChanged);
      _ctrl?.dispose();
      _ctrl = null;

      // Close the old LSP document before opening the new one.
      if (oldPath != null) unawaited(_vm?.lspCloseDocument(oldPath));
      _diagSub?.cancel();
      _diagSub = null;
      _diagnostics = const <LspDiagnostic>[];

      // Recreate the controller with new content.
      final text = _editableText;
      if (text != null) {
        _baseline = text;
        _ctrl = CodeEditingController(text: text, language: _language)
          ..addListener(_onCtrlChanged);
        widget.session.saveDraft = _save;
        _startLsp(text);
      } else {
        widget.session.saveDraft = null;
      }
      // Force a rebuild.
      setState(() {});
      return;
    }

    final text = _editableText;
    // Exit editing if the type unexpectedly becomes non-editable.
    if (text == null) {
      if (_editing) setState(() => _editing = false);
      return;
    }
    // Synchronize clean content after an external watcher reload. Preserve a
    // user's dirty buffer for last-write-wins on save. Defer until post-build to
    // avoid setState during build through setDirty -> notifyListeners.
    if (!_dirty && _ctrl != null && _ctrl!.text != text) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_dirty && _ctrl != null && _ctrl!.text != text) {
          _ctrl!.text = text;
          _baseline = text;
          // Keep LSP synchronized after an agent changes the file on disk.
          unawaited(_vm?.lspChangeDocument(widget.session.path, text));
        }
      });
    }
    // Focus the editor when tab selection makes this the focused tab.
    if (widget.focused && !old.focused) _focusEditorIfActive();
  }

  /// Report whether an editor is visible and can receive focus.
  ///
  /// Text/code always qualifies; Markdown/SVG qualifies only in Source mode.
  bool get _editingNow => _editableText != null && (!_hasPreview || _editing);

  /// Restore editor focus after Format, Save, or Discard.
  ///
  /// Runs post-frame because toolbar actions can rebuild and steal a newly
  /// requested focus.
  void _refocusEditor() {
    if (!mounted || _ctrl == null || !_editingNow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  /// Focus the editor only when this tab is focused and editing.
  void _focusEditorIfActive() {
    if (!widget.focused || !_editingNow || _ctrl == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.focused) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    if (widget.session.saveDraft == _save) widget.session.saveDraft = null;
    _cancelLspDebounce();
    _diagSub?.cancel();
    if (_vm != null) unawaited(_vm!.lspCloseDocument(widget.session.path));
    _ctrl?.removeListener(_onCtrlChanged);
    _ctrl?.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onCtrlChanged() {
    _updateDirty(_ctrl != null && _ctrl!.text != _baseline);
    // Debounce user edits before notifying LSP to coalesce typing bursts.
    final ctrl = _ctrl;
    if (ctrl == null) return;
    _cancelLspDebounce();
    final path = widget.session.path;
    final text = ctrl.text;
    _lspDebounce = Timer(const Duration(milliseconds: 400), () {
      _lspDebounce = null;
      if (!mounted) return;
      final vm = _vm;
      if (vm == null) return;
      ownAsync(vm.lspChangeDocument(path, text));
    });
  }

  void _cancelLspDebounce() {
    _lspDebounce?.cancel();
    _lspDebounce = null;
  }

  /// Synchronize dirty state locally and with the session's tab/dialog indicators.
  void _updateDirty(bool value) {
    if (value != _dirty) setState(() => _dirty = value);
    widget.session.setDirty(value);
  }

  void _toggleEditing() {
    setState(() => _editing = !_editing);
    // Convert a preview into a normal tab when editing starts.
    if (_editing) {
      widget.session.pin();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  void _discard() {
    final ctrl = _ctrl;
    if (ctrl == null || !_dirty || _saving) return;
    // Restore the last saved baseline and clear dirty state.
    ctrl.text = _baseline;
    _updateDirty(false);
  }

  /// Resolve the external `%FILE%` formatter configured for this language.
  ///
  /// Returns `null` when Settings defines none.
  String? _externalFormatter() {
    final lang = languageForPath(widget.session.path)?.id;
    if (lang == null) return null;
    return context.read<SettingsController>().settings.lspFormatters[lang];
  }

  bool get _formatOnSave =>
      context.read<SettingsController>().settings.formatOnSave;

  /// Persist the buffer and report success, including when nothing needs saving.
  ///
  /// With format-on-save, JSON/LSP buffer formatters run before writing. External
  /// file-based formatters run after writing and trigger a reread.
  Future<bool> _save() async {
    final ctrl = _ctrl;
    if (ctrl == null) return false;
    if (!_dirty || _saving) return true;

    final external = _externalFormatter();
    final formatOnSave = _formatOnSave;

    // Format the buffer before writing only when no external formatter exists.
    if (formatOnSave && external == null) {
      final formatted = await _formatBuffer();
      if (!mounted) return false;
      if (formatted != null && formatted != ctrl.text) {
        _applyToBuffer(formatted);
      }
    }

    final content = ctrl.text;
    setState(() => _saving = true);
    final ok = await widget.onSave(content);
    if (!mounted) return ok;
    setState(() => _saving = false);
    if (ok) {
      _baseline = content;
      _updateDirty(false);
    }

    // Run the external formatter on the written file, then reread it.
    if (ok && formatOnSave && external != null) {
      await _runExternalFormatter(external);
    }
    return ok;
  }

  /// Format on demand with ⇧⌘F.
  ///
  /// A file-based external formatter takes precedence; otherwise format JSON
  /// through the standard library or use LSP on the buffer.
  Future<void> _format() async {
    final ctrl = _ctrl;
    if (ctrl == null || _saving) return;
    final external = _externalFormatter();
    if (external != null) {
      // For file-based formatting, write the current buffer, run, and reread.
      final ok = await _save();
      if (!ok || !mounted) return;
      await _runExternalFormatter(external);
      return;
    }
    final formatted = await _formatBuffer();
    if (!mounted || formatted == null || formatted == ctrl.text) return;
    _applyToBuffer(formatted);
  }

  /// Format current buffer content without writing it.
  ///
  /// Uses the standard library for JSON and LSP otherwise. Returns `null` when
  /// no formatter can produce content.
  Future<String?> _formatBuffer() async {
    final ctrl = _ctrl;
    if (ctrl == null) return null;
    final path = widget.session.path;
    final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
    if (ext == 'json') {
      try {
        return '${const JsonEncoder.withIndent('  ').convert(jsonDecode(ctrl.text))}\n';
      } catch (_) {
        return null; // Invalid JSON.
      }
    }
    final vm = _vm;
    if (vm == null) return null;
    final edits = await vm.lspFormat(path, ctrl.text);
    if (edits.isEmpty) return null;
    return applyTextEdits(ctrl.text, edits);
  }

  /// Run the external formatter on disk and reread the buffer.
  Future<void> _runExternalFormatter(String command) async {
    final result = await runFormatterCommand(command, widget.session.path);
    if (!mounted) return;
    await result.fold((_) => _reloadFromDisk(), (_) async {});
  }

  /// Reload disk content into the buffer after external formatting.
  Future<void> _reloadFromDisk() async {
    try {
      final fresh = await File(widget.session.path).readAsString();
      if (!mounted) return;
      final ctrl = _ctrl;
      if (ctrl == null || ctrl.text == fresh) return;
      _applyToBuffer(fresh);
      _baseline = fresh;
      _updateDirty(false);
      unawaited(_vm?.lspChangeDocument(widget.session.path, fresh));
    } catch (e) {
      // Non-invasive signal only: preserve the prior fallback (no buffer change)
      // so a formatter/read failure does not silently mask as success.
      debugPrint(fileViewerReloadFailureDiagnostic(e));
    }
  }

  /// Apply [text] to the buffer while preserving the cursor when possible.
  void _applyToBuffer(String text) {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final caret = ctrl.selection.baseOffset;
    ctrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: caret < 0 ? 0 : caret.clamp(0, text.length),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final editable = _editableText != null;
    // Text/code without preview edits directly; Markdown/SVG edits only in Source.
    final editingNow = editable && (!_hasPreview || _editing);

    final Widget body = switch (widget.session.view) {
      FileViewMarkdown(:final text) =>
        editingNow
            ? _editor()
            : SelectionArea(child: _Scroll(child: AgentMarkdown(text))),
      FileViewSvg(:final text) =>
        editingNow ? _editor() : _SvgPreview(source: text),
      FileViewText(:final text, :final language) =>
        editingNow
            ? _editor()
            : _TextView(
                text: text,
                language: language,
                diagnostics: _diagnostics,
              ),
      FileViewImage(:final path) => _ImageView(path: path),
      FileViewAudio(:final path) => MediaView(
        key: ValueKey('media:$path'),
        path: path,
        kind: MediaKind.audio,
        active: widget.active,
      ),
      FileViewVideo(:final path) => MediaView(
        key: ValueKey('media:$path'),
        path: path,
        kind: MediaKind.video,
        active: widget.active,
      ),
      FileViewUnsupported() => Center(
        child: Text(
          'Can\'t open this file.',
          style: context.typo.body.copyWith(color: colors.text3),
        ),
      ),
    };

    final Widget content = ColoredBox(
      color: colors.panel,
      child: Column(
        children: [
          Expanded(child: body),
          if (editable)
            _Toolbar(
              hasPreview: _hasPreview,
              editing: editingNow,
              previewing: _hasPreview && !_editing,
              dirty: _dirty,
              saving: _saving,
              onToggle: _toggleEditing,
              onSave: () => _save().whenComplete(_refocusEditor),
              onDiscard: () {
                _discard();
                _refocusEditor();
              },
              onFormat: () => _format().whenComplete(_refocusEditor),
            ),
        ],
      ),
    );

    // Wrap the entire viewer in Cmd+S/Ctrl+S handling. Markdown/SVG enters Source
    // through the footer while focus remains outside the field, so wrapping only
    // the editor would make the shortcut unreachable.
    if (!editable) return content;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            _save(),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            _save(),
        const SingleActivator(
          LogicalKeyboardKey.keyF,
          meta: true,
          shift: true,
        ): () =>
            _format(),
        const SingleActivator(
          LogicalKeyboardKey.keyF,
          control: true,
          shift: true,
        ): () =>
            _format(),
      },
      child: content,
    );
  }

  Widget _editor() {
    final ctrl = _ctrl;
    if (ctrl == null) return const SizedBox.shrink();
    return CodeEditor(controller: ctrl, focusNode: _focus);
  }
}

/// Provide compact controls beneath editable file content.
///
/// Markdown/SVG with [hasPreview] gains Preview/Source switching, while text/code
/// edits directly. Save and Discard appear during [editing], with a dirty dot for
/// unsaved changes.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.hasPreview,
    required this.editing,
    required this.previewing,
    required this.dirty,
    required this.saving,
    required this.onToggle,
    required this.onSave,
    required this.onDiscard,
    required this.onFormat,
  });

  /// Indicate whether Markdown/SVG has a rendered Preview/Source switch.
  final bool hasPreview;

  /// Indicate editor mode: source for Markdown/SVG, always true for text/code.
  final bool editing;

  /// Indicate rendered preview mode when [hasPreview] applies.
  final bool previewing;
  final bool dirty;
  final bool saving;
  final VoidCallback onToggle;
  final VoidCallback onSave;
  final VoidCallback onDiscard;
  final VoidCallback onFormat;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          const Spacer(),
          if (dirty && !saving)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: colors.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          if (editing) ...[
            _BarButton(
              icon: Icons.auto_fix_high,
              label: 'Format',
              tooltip: 'Format (⇧⌘F)',
              enabled: !saving,
              onTap: onFormat,
            ),
            const SizedBox(width: 2),
            _BarButton(
              icon: Icons.undo,
              label: 'Discard',
              tooltip: 'Discard changes',
              enabled: dirty && !saving,
              onTap: onDiscard,
            ),
            const SizedBox(width: 2),
            _BarButton(
              icon: saving ? Icons.hourglass_empty : Icons.save_outlined,
              label: 'Save',
              tooltip: 'Save (⌘S)',
              enabled: dirty && !saving,
              onTap: onSave,
            ),
          ],
          if (hasPreview) ...[
            const SizedBox(width: 4),
            _Segmented(
              leftLabel: 'Preview',
              rightLabel: 'Source',
              leftActive: previewing,
              onTap: onToggle,
            ),
          ],
        ],
      ),
    );
  }
}

/// Toggle between two view and edit states by clicking either side.
class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.leftLabel,
    required this.rightLabel,
    required this.leftActive,
    required this.onTap,
  });

  final String leftLabel;
  final String rightLabel;
  final bool leftActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;

    Widget seg(String label, bool active) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? colors.panel : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: typo.tab.copyWith(
          color: active ? colors.text : colors.text3,
          fontSize: 12,
        ),
      ),
    );

    return HoverTap(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: colors.panel2,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [seg(leftLabel, leftActive), seg(rightLabel, !leftActive)],
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = enabled ? colors.text : colors.text4;
    return Tooltip(
      tooltip: (context) => TooltipContainer(child: Text(tooltip)),
      child: HoverTap(
        borderRadius: BorderRadius.circular(5),
        onTap: enabled ? onTap : () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: context.typo.tab.copyWith(color: color, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
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

/// Present selectable read-only text/code beside a fixed line-number gutter.
///
/// Long lines scroll horizontally while line numbers remain fixed and
/// non-selectable.
class _TextView extends StatefulWidget {
  const _TextView({
    required this.text,
    this.language,
    this.diagnostics = const <LspDiagnostic>[],
  });

  final String text;

  /// Supply an extension-based highlighting language, or `null` for no hint.
  final String? language;

  /// Supply LSP diagnostics to underline consistently with the editor.
  final List<LspDiagnostic> diagnostics;

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
    final typo = context.typo;
    // Use the syntax theme's own background rather than the app theme so One
    // Dark/Dracula remain dark in light mode. Font size comes from configurable
    // `typo.mono` under Settings → Code.
    final syntax = context.syntax;
    final codeStyle = typo.mono.copyWith(color: syntax.base);
    // Render highlight.js/theme spans when appropriate; fall back to plain text
    // when language is unknown or the file is too large.
    final codeSpan = buildCodeSpan(
      context,
      source: widget.text,
      language: widget.language,
      baseStyle: codeStyle,
      diagnostics: diagnosticRangesFor(widget.text, widget.diagnostics),
    );
    final numStyle = typo.mono.copyWith(
      color: syntax.base.withValues(alpha: 0.4),
    );

    // Count newline separators while retaining a final unterminated line and one
    // line for an empty file, matching code metrics for gutter alignment.
    final lineCount = '\n'.allMatches(widget.text).length + 1;

    // Nest horizontal scrolling inside vertical scrolling. The outer horizontal
    // scrollbar stays pinned at the viewport bottom. Its notifications arrive at
    // depth 1, so notificationPredicate filters by depth; vertical stays at edge.
    return ColoredBox(
      color: syntax.background,
      child: Scrollbar(
        controller: _horizontal,
        thumbVisibility: true,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        notificationPredicate: (notification) => notification.depth == 1,
        child: Scrollbar(
          controller: _vertical,
          child: SingleChildScrollView(
            controller: _vertical,
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Right-align fixed gutter numbers outside horizontal scrolling.
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
                Container(width: 1, color: syntax.base.withValues(alpha: 0.15)),
                // Keep code selectable and horizontally scroll long lines.
                Expanded(
                  child: SingleChildScrollView(
                    controller: _horizontal,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(left: 14, right: 16),
                    child: codeSpan == null
                        ? SelectableText(widget.text, style: codeStyle)
                        : SelectableText.rich(codeSpan),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Render SVG from source text rather than a file path.
///
/// This keeps preview aligned with saved content after every save without a file
/// cache.
class _SvgPreview extends StatelessWidget {
  const _SvgPreview({required this.source});
  final String source;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      maxScale: 8,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SvgPicture.string(source, fit: BoxFit.contain),
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
                    'Could not load the image.',
                    style: context.typo.body.copyWith(color: colors.text3),
                  ),
                ),
        ),
      ),
    );
  }
}
