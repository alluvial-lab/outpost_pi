import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cockpit/app/cockpit/domain/entities/pi_command.dart';
import 'package:cockpit/app/cockpit/domain/entities/prompt_image.dart';
import 'package:cockpit/app/cockpit/domain/entities/rpc_event.dart'
    show RelayStatus;
import 'package:cockpit/app/cockpit/domain/entities/thinking_level.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_session.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/cockpit/ui/widgets/model_picker.dart';
import 'package:cockpit/app/core/ui/file_icons/file_icons.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Compose agent prompts with model, effort, approval, and send controls.
///
/// Model and effort changes invoke `set_model` and `set_thinking_level`;
/// approval remains a UI preference.
class AgentComposer extends StatefulWidget {
  const AgentComposer({super.key, required this.session});
  final AgentSession session;

  @override
  State<AgentComposer> createState() => _AgentComposerState();
}

class _AgentComposerState extends State<AgentComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  bool _focused = false;
  bool _hasText = false;

  // --- Slash commands (/) — the entire input starts with '/'. ---
  String? _cmdQuery; // Text after '/'; null outside command mode.
  bool _cmdSuppress = false;

  // --- File mentions (@) — an '@token' adjacent to the cursor. ---
  ({int start, String query})? _mention;
  List<String> _fileMatches = const <String>[];
  bool _fileSuppress = false;
  Timer? _searchDebounce;
  int _searchSeq = 0;

  /// Track the highlighted index in the active command or file overlay.
  int _index = 0;

  /// Hold composer attachments outside the editable text.
  ///
  /// Images become preview chips and are sent through `images`. Files become
  /// icon/name chips whose `@<rel>` references are rebuilt when sending.
  final List<_Attachment> _attachments = <_Attachment>[];
  static const int _maxImages = 3;
  int _pasteSeq = 0;

  /// Indicate that OS files are being dragged over the input.
  bool _osDragOver = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    // Register input focus for CockpitPage's ⌘L/Ctrl+L shortcut.
    widget.session.requestComposerFocus = _focusInput;
  }

  void _focusInput() {
    if (mounted) _inputFocus.requestFocus();
  }

  /// Pick external files, attaching images as vision input and others as chips.
  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      dialogTitle: 'Attach file',
    );
    if (result == null) return;
    for (final file in result.files) {
      final path = file.path;
      if (path == null) continue;
      if (_isImageName(file.name)) {
        _addImage(
          _Attachment(name: file.name, isImage: true, bytes: file.bytes),
        );
      } else {
        _addFileFromPath(path);
      }
    }
  }

  /// Handle native OS drops, attaching images as vision input and others as chips.
  Future<void> _onOsDrop(List<DropItem> items) async {
    for (final item in items) {
      final path = item.path;
      if (path.isEmpty) continue;
      if (_isImageName(item.name)) {
        final bytes = await item.readAsBytes();
        _addImage(_Attachment(name: item.name, isImage: true, bytes: bytes));
      } else {
        _addFileFromPath(path);
      }
    }
  }

  /// Paste clipboard images as vision input and copied files as chips.
  ///
  /// Falls back to inserting ordinary clipboard text at the cursor.
  Future<void> _pasteFromClipboard() async {
    final imageBytes = await Pasteboard.image;
    if (imageBytes != null && imageBytes.isNotEmpty) {
      _addImage(
        _Attachment(
          name: 'colado-${++_pasteSeq}.png',
          isImage: true,
          bytes: imageBytes,
        ),
      );
      return;
    }
    final files = await Pasteboard.files();
    if (files.isNotEmpty) {
      for (final p in files) {
        _addFileFromPath(p);
      }
      return;
    }
    final text = await Pasteboard.text;
    if (text != null && text.isNotEmpty) _insertText(text);
  }

  /// Insert [text] at the cursor as the plain-text paste fallback.
  void _insertText(String text) {
    final value = _controller.value;
    final sel = value.selection;
    final start = sel.isValid ? sel.start : value.text.length;
    final end = sel.isValid ? sel.end : value.text.length;
    final newText = value.text.replaceRange(start, end, text);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  /// Add an image attachment while enforcing [_maxImages].
  void _addImage(_Attachment image) {
    if (!mounted) return;
    final count = _attachments.where((a) => a.isImage).length;
    if (count >= _maxImages) {
      _notifyLimit();
      return;
    }
    setState(() => _attachments.add(image));
  }

  /// Create a file chip that emits `@<path>` when sent.
  void _addFileFromPath(String path) {
    _addFileMention(path, _basename(path));
  }

  /// Restore input focus after an OS or Files-panel drop steals it.
  ///
  /// Runs post-frame because native drops release focus only after the event
  /// settles.
  void _restoreInputFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocus.requestFocus();
    });
  }

  /// Add a file chip from a reference without duplicating it.
  void _addFileMention(String mention, String name) {
    if (!mounted) return;
    if (_attachments.any((a) => !a.isImage && a.mention == mention)) return;
    setState(() {
      _attachments.add(
        _Attachment(name: name, isImage: false, mention: mention),
      );
    });
  }

  void _notifyLimit() {
    showToast(
      context: context,
      location: ToastLocation.bottomRight,
      builder: (context, overlay) => const SurfaceCard(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Maximum of $_maxImages images.'),
        ),
      ),
    );
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    if (widget.session.requestComposerFocus == _focusInput) {
      widget.session.requestComposerFocus = null;
    }
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  int get _cursor {
    final sel = _controller.selection;
    return sel.isValid ? sel.end : _controller.text.length;
  }

  bool _isSpace(String c) => c == ' ' || c == '\n' || c == '\t';

  void _onChanged() {
    final text = _controller.text;
    _hasText = text.trim().isNotEmpty;

    // 1) Commands take precedence when the entire input starts with '/'.
    if (text.startsWith('/')) {
      _mention = null;
      _fileMatches = const <String>[];
      if (_cmdSuppress) {
        _cmdQuery = null;
      } else {
        if (_cmdQuery != text.substring(1)) _index = 0;
        _cmdQuery = text.substring(1);
      }
      setState(() {});
      return;
    }
    _cmdSuppress = false;
    _cmdQuery = null;

    // 2) Match a file mention from the '@token' before the cursor.
    final mention = _activeMention(text, _cursor);
    if (mention == null) {
      _fileSuppress = false;
      _mention = null;
      _fileMatches = const <String>[];
    } else if (_fileSuppress) {
      _mention = null;
    } else {
      if (_mention?.query != mention.query) _index = 0;
      _mention = mention;
      _searchFiles(mention.query);
    }
    setState(() {});
  }

  /// Find the `@token` immediately before the cursor.
  ///
  /// The token must start at the input boundary or after a space and contain no
  /// intervening spaces. Returns `null` when no mention is active.
  ({int start, String query})? _activeMention(String text, int cursor) {
    if (cursor < 0 || cursor > text.length) cursor = text.length;
    var i = cursor - 1;
    while (i >= 0) {
      final c = text[i];
      if (c == '@') {
        final prevOk = i == 0 || _isSpace(text[i - 1]);
        if (!prevOk) return null;
        final query = text.substring(i + 1, cursor);
        if (query.contains(RegExp(r'\s'))) return null;
        return (start: i, query: query);
      }
      if (_isSpace(c)) return null;
      i--;
    }
    return null;
  }

  void _searchFiles(String query) {
    _searchDebounce?.cancel();
    final vm = context.read<CockpitViewModel>();
    final cwd = widget.session.workingDirectory;
    final seq = ++_searchSeq;
    _searchDebounce = Timer(const Duration(milliseconds: 120), () async {
      final results = await vm.searchFiles(cwd, query);
      if (!mounted || seq != _searchSeq) return;
      setState(() => _fileMatches = results);
    });
  }

  // --- slash command data ---
  static const List<PiCommand> _builtins = <PiCommand>[
    PiCommand(
      name: 'new',
      description: 'New session — clears the conversation',
    ),
    PiCommand(name: 'compact', description: 'Compacts the agent context'),
  ];

  /// Combine built-ins with extension commands while suppressing `/outpost-pi`.
  List<PiCommand> get _allCommands => <PiCommand>[
    ..._builtins,
    ...widget.session.projection.controls.commands.where(
      (c) => c.name != 'outpost-pi' && !c.name.startsWith('outpost-pi '),
    ),
  ];

  List<PiCommand> get _cmdMatches {
    final query = _cmdQuery;
    if (query == null) return const <PiCommand>[];
    final q = query.toLowerCase();
    return _allCommands
        .where((c) => c.name.toLowerCase().startsWith(q))
        .toList(growable: false);
  }

  bool _runBuiltin(String name) {
    switch (name) {
      case 'new':
        widget.session.startNewSession();
        return true;
      case 'compact':
        widget.session.compact();
        return true;
      default:
        return false;
    }
  }

  // --- Overlays: command or file, never both. ---
  bool get _cmdOpen => _cmdQuery != null && _cmdMatches.isNotEmpty;
  bool get _fileOpen => _mention != null && _fileMatches.isNotEmpty;
  bool get _overlayOpen => _cmdOpen || _fileOpen;
  int get _activeCount =>
      _cmdOpen ? _cmdMatches.length : (_fileOpen ? _fileMatches.length : 0);

  /// Build active-overlay entries in palette format.
  List<_Suggest> get _suggestions {
    if (_cmdOpen) {
      return [
        for (final c in _cmdMatches)
          _Suggest(
            primary: '/${c.name}',
            secondary: c.description.isEmpty ? null : c.description,
          ),
      ];
    }
    if (_fileOpen) {
      return [
        for (final p in _fileMatches)
          _Suggest(
            primary: _basename(p),
            secondary: _dirname(p),
            icon: Icons.insert_drive_file_outlined,
          ),
      ];
    }
    return const <_Suggest>[];
  }

  String _basename(String p) {
    final i = p.lastIndexOf('/');
    return i == -1 ? p : p.substring(i + 1);
  }

  String? _dirname(String p) {
    final i = p.lastIndexOf('/');
    return i == -1 ? null : p.substring(0, i);
  }

  // --- Keyboard navigation and acceptance. ---
  void _onEnter() {
    if (_cmdOpen) {
      _acceptCommand(_index);
    } else if (_fileOpen) {
      _acceptFile(_index);
    } else {
      _submit();
    }
  }

  void _onSelectIndex(int i) {
    if (_cmdOpen) {
      _acceptCommand(i);
    } else if (_fileOpen) {
      _acceptFile(i);
    }
  }

  void _moveIndex(int delta) {
    final n = _activeCount;
    if (n == 0) return;
    setState(() => _index = (_index + delta + n) % n);
  }

  void _accept() => _onSelectIndex(_index);

  void _dismissOverlay() {
    setState(() {
      if (_cmdOpen) {
        _cmdSuppress = true;
        _cmdQuery = null;
      } else if (_fileOpen) {
        _fileSuppress = true;
        _mention = null;
        _fileMatches = const <String>[];
      }
    });
  }

  void _acceptCommand(int index) {
    final matches = _cmdMatches;
    if (matches.isEmpty) return;
    final cmd = matches[index.clamp(0, matches.length - 1)];
    _cmdSuppress =
        true; // Set before changing text because the listener reads it.
    final value = '/${cmd.name} ';
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  /// Accept a file from the `@` overlay and replace the typed query with a chip.
  ///
  /// Search returns a cwd-relative path; convert it to an absolute path because
  /// relative mentions are ambiguous.
  void _acceptFile(int index) {
    final mention = _mention;
    final matches = _fileMatches;
    if (mention == null || matches.isEmpty) return;
    final rel = matches[index.clamp(0, matches.length - 1)];
    final text = _controller.text;
    final before = text.substring(0, mention.start);
    final after = text.substring(_cursor);
    _fileSuppress = true;
    _controller.value = TextEditingValue(
      text: before + after,
      selection: TextSelection.collapsed(offset: before.length),
    );
    _mention = null;
    _fileMatches = const <String>[];
    final cwd = widget.session.workingDirectory;
    final abs = cwd.isEmpty
        ? rel
        : (cwd.endsWith('/') ? '$cwd$rel' : '$cwd/$rel');
    _addFileMention(abs, _basename(abs));
    _inputFocus.requestFocus();
  }

  Future<void> _submit() async {
    final session = widget.session;
    final projection = session.projection;
    if (projection.turn.canStop) {
      session.stop();
      return;
    }
    final typed = _controller.text.trim();
    final attachments = List<_Attachment>.of(_attachments);
    if (typed.isEmpty && attachments.isEmpty) return;

    // Route a pure built-in (/new, /compact) through its dedicated RPC. A
    // command with attachments is sent as a prompt instead.
    if (attachments.isEmpty &&
        typed.startsWith('/') &&
        _runBuiltin(typed.substring(1).split(' ').first)) {
      _resetInput();
      return;
    }

    // Rebuild file mentions (`@<path>`) from chips and append them to the text;
    // the agent reads them through tools and the message renders them as badges.
    final fileMentions = attachments
        .where((a) => !a.isImage && a.mention != null)
        .map((a) => '@${a.mention}');
    final message = <String>[
      if (typed.isNotEmpty) typed,
      ...fileMentions,
    ].join(' ');

    // Clear the UI immediately for responsiveness; image normalization is async.
    _resetInput();

    // Normalize every image to 8-bit sRGB PNG. The macOS clipboard often
    // supplies Display P3/16-bit data rejected by vision providers, which made
    // paste fail while file attachment worked. Also shrink huge screenshots.
    final images = <PromptImage>[];
    for (final a in attachments) {
      if (!a.isImage || a.bytes == null) continue;
      final png = await _toStandardPng(a.bytes!);
      images.add(PromptImage(data: base64Encode(png), mimeType: 'image/png'));
    }

    session.send(message, images: images);
  }

  /// Re-encode [bytes] as a standard 8-bit sRGB PNG.
  ///
  /// Shrinks images whose longest side exceeds [maxSide]. Returns the original
  /// bytes when decoding or encoding fails.
  Future<Uint8List> _toStandardPng(
    Uint8List bytes, {
    int maxSide = 1568,
  }) async {
    try {
      var codec = await ui.instantiateImageCodec(bytes);
      var image = (await codec.getNextFrame()).image;
      final longest = math.max(image.width, image.height);
      if (longest > maxSide) {
        final wide = image.width >= image.height;
        image.dispose();
        codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: wide ? maxSide : null,
          targetHeight: wide ? null : maxSide,
        );
        image = (await codec.getNextFrame()).image;
      }
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data?.buffer.asUint8List() ?? bytes;
    } catch (_) {
      return bytes;
    }
  }

  /// Clear input and attachments after sending or executing a built-in.
  void _resetInput() {
    _controller.clear();
    _cmdSuppress = false;
    _cmdQuery = null;
    _fileSuppress = false;
    _mention = null;
    _fileMatches = const <String>[];
    if (_attachments.isNotEmpty) {
      setState(() => _attachments.clear());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final session = widget.session;
    final projection = session.projection;
    final turn = projection.turn;
    final canStop = turn.canStop;
    final controlsEnabled = projection.isAlive && !turn.working;

    // A native OS drop attaches an image or creates an `@` reference. The child
    // DragTarget<String> handles internal drag-and-drop from the Files panel.
    return DropTarget(
      onDragEntered: (_) {
        if (!_osDragOver) setState(() => _osDragOver = true);
      },
      onDragExited: (_) {
        if (_osDragOver) setState(() => _osDragOver = false);
      },
      onDragDone: (detail) {
        if (_osDragOver) setState(() => _osDragOver = false);
        _onOsDrop(detail.files);
        _restoreInputFocus();
      },
      child: DragTarget<String>(
        onAcceptWithDetails: (d) {
          _addFileFromPath(d.data);
          _restoreInputFocus();
        },
        builder: (context, candidate, rejected) {
          final dragging = candidate.isNotEmpty;
          final borderColor = (_focused || dragging || _osDragOver)
              ? colors.accent
              : (controlsEnabled ? colors.border2 : colors.border);
          final box = Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colors.panel2,
              borderRadius: BorderRadius.circular(10),
              // Use only the accent border, not a shadow, to signal focus.
              border: Border.all(color: borderColor),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Show command (`/`) or file (`@`) suggestions above the input.
                if (_overlayOpen)
                  _SuggestPalette(
                    items: _suggestions,
                    selected: _index,
                    onSelect: _onSelectIndex,
                  ),
                // Show image thumbnails and other attachment chips above input.
                if (_attachments.isNotEmpty)
                  _AttachmentStrip(
                    attachments: _attachments,
                    onRemove: _removeAttachment,
                  ),
                // Warn when the current text-only model cannot see the image.
                if (_attachments.any((a) => a.isImage) &&
                    !(projection.controls.model?.supportsImages ?? false))
                  const _ImageModelWarning(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                  child: Focus(
                    onFocusChange: (f) => setState(() => _focused = f),
                    child: CallbackShortcuts(
                      bindings: <ShortcutActivator, VoidCallback>{
                        const SingleActivator(LogicalKeyboardKey.enter):
                            _onEnter,
                        // Cmd/Ctrl+V attaches clipboard images/files and pastes
                        // ordinary text normally.
                        const SingleActivator(
                          LogicalKeyboardKey.keyV,
                          meta: true,
                        ): _pasteFromClipboard,
                        const SingleActivator(
                          LogicalKeyboardKey.keyV,
                          control: true,
                        ): _pasteFromClipboard,
                        if (_overlayOpen) ...{
                          const SingleActivator(
                            LogicalKeyboardKey.arrowDown,
                          ): () =>
                              _moveIndex(1),
                          const SingleActivator(
                            LogicalKeyboardKey.arrowUp,
                          ): () =>
                              _moveIndex(-1),
                          const SingleActivator(LogicalKeyboardKey.tab):
                              _accept,
                          const SingleActivator(LogicalKeyboardKey.escape):
                              _dismissOverlay,
                        },
                      },
                      child: TextField(
                        controller: _controller,
                        focusNode: _inputFocus,
                        minLines: 2,
                        maxLines: 6,
                        style: context.typo.body.copyWith(
                          fontSize: 13.5,
                          color: colors.text,
                        ),
                        // Keep the field chromeless inside the composer container,
                        // without its own background or border.
                        decoration: const BoxDecoration(),
                        padding: EdgeInsets.zero,
                        placeholder: Text(
                          'Message to the agent, use @files or /commands',
                          style: context.typo.body.copyWith(
                            fontSize: 13.5,
                            color: colors.text3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 7),
                  child: Row(
                    children: [
                      _BarIcon(
                        icon: Icons.add,
                        tooltip: 'Attach file',
                        onTap: _pickAttachment,
                      ),
                      _ModelChip(session: session, enabled: controlsEnabled),
                      // Show effort only for reasoning models that Pi can use it with.
                      if (projection.controls.model?.reasoning ?? false)
                        _EffortChip(session: session, enabled: controlsEnabled),
                      // Fill the context-usage indicator as the window fills.
                      _ContextGauge(session: session),
                      _RelayButton(session: session),
                      const Spacer(),
                      // Show the spinner and turn timer only while working.
                      _TurnIndicator(session: session),
                      _SendButton(
                        streaming: canStop,
                        ready: _hasText || _attachments.isNotEmpty,
                        onTap: _submit,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
          return Stack(
            clipBehavior: Clip.none,
            children: [
              box,
              // Show the shortcut hint only for the active tab while input is
              // unfocused; background tabs never display it.
              if (context.select<CockpitViewModel, bool>(
                    (vm) => vm.focusedAgent?.id == widget.session.id,
                  ) &&
                  !_focused &&
                  controlsEnabled)
                const Positioned(top: 7, right: 10, child: _ShortcutHint()),
            ],
          );
        },
      ),
    );
  }
}

/// Show a subtle pill for the input-focus shortcut (⌘L / Ctrl+L).
class _ShortcutHint extends StatelessWidget {
  const _ShortcutHint();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: colors.panel3,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          isMac ? '⌘L' : 'Ctrl+L',
          style: context.typo.label.copyWith(
            fontSize: 10.5,
            color: colors.text3,
          ),
        ),
      ),
    );
  }
}

/// Describe a command or file suggestion shown in the overlay.
class _Suggest {
  const _Suggest({required this.primary, this.secondary, this.icon});
  final String primary; // mono
  final String? secondary; // Dimmed trailing text.
  final IconData? icon;
}

/// List command (`/`) or file (`@`) suggestions above the input.
///
/// Highlights keyboard selection, accepts clicks, and scrolls beyond its maximum
/// height.
class _SuggestPalette extends StatelessWidget {
  const _SuggestPalette({
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  final List<_Suggest> items;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return Container(
      constraints: const BoxConstraints(maxHeight: 210),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 5),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          final active = i == selected;
          return HoverTap(
            onTap: () => onSelect(i), // GestureDetector preserves input focus.
            color: active ? colors.panel3 : Colors.transparent,
            borderRadius: BorderRadius.zero,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            child: Row(
              children: [
                if (item.icon != null) ...[
                  Icon(
                    item.icon,
                    size: 13,
                    color: active ? colors.accentText : colors.text3,
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    item.primary,
                    overflow: TextOverflow.ellipsis,
                    style: typo.mono.copyWith(
                      fontSize: 12.5,
                      color: active ? colors.accentText : colors.text,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (item.secondary != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.secondary!,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: typo.label.copyWith(color: colors.text3),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: HoverTap(
        borderRadius: BorderRadius.circular(5),
        onTap: enabled ? onTap : null,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: iconColor ?? colors.text3),
            const SizedBox(width: 6),
            Text(
              label,
              style: context.typo.label.copyWith(
                fontSize: 12.5,
                color: colors.text2,
              ),
            ),
            Icon(Icons.keyboard_arrow_down, size: 13, color: colors.text4),
          ],
        ),
      ),
    );
  }
}

class _ModelChip extends StatelessWidget {
  const _ModelChip({required this.session, required this.enabled});
  final AgentSession session;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final controls = session.projection.controls;
    final model = controls.model;
    return _Chip(
      icon: Icons.auto_awesome,
      iconColor: context.colors.accentText,
      label: model?.name ?? 'model',
      enabled: enabled && controls.models.isNotEmpty,
      onTap: () async {
        final picked = await showModelPicker(
          context,
          models: controls.models,
          current: model,
        );
        if (picked != null) session.changeModel(picked);
      },
    );
  }
}

class _EffortChip extends StatelessWidget {
  const _EffortChip({required this.session, required this.enabled});
  final AgentSession session;
  final bool enabled;

  Future<void> _show(BuildContext context) async {
    // Use only the levels accepted by this model's thinkingLevelMap.
    final controls = session.projection.controls;
    final levels = ThinkingLevel.availableFor(
      controls.model?.thinkingLevelMap ?? const <String, String?>{},
    );
    final current = controls.thinkingLevel;
    final level = await showAppMenu<ThinkingLevel>(
      context,
      minWidth: 170,
      items: [
        for (final l in levels)
          AppMenuItem(
            value: l,
            label: l.label,
            icon: Icons.psychology_alt_outlined,
            selected: l == current,
          ),
      ],
    );
    if (level != null) session.changeThinking(level);
  }

  @override
  Widget build(BuildContext context) {
    return _Chip(
      icon: Icons.psychology_alt_outlined,
      label: session.projection.controls.thinkingLevel.label,
      enabled: enabled,
      onTap: () => _show(context),
    );
  }
}

/// Show streaming activity and elapsed turn time while the agent works.
///
/// Counts through seconds, minutes, and hours, then disappears when the turn ends.
class _TurnIndicator extends StatefulWidget {
  const _TurnIndicator({required this.session});
  final AgentSession session;

  @override
  State<_TurnIndicator> createState() => _TurnIndicatorState();
}

class _TurnIndicatorState extends State<_TurnIndicator> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
    _sync();
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    _ticker?.cancel();
    super.dispose();
  }

  void _onSession() {
    _sync();
    if (mounted) setState(() {});
  }

  /// Start or stop one-second ticks as the turn begins or ends.
  void _sync() {
    final turn = widget.session.projection.turn;
    final active = turn.working && turn.startedAt != null;
    if (active && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!active && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  String _format(Duration d) {
    final s = d.inSeconds;
    if (s < 60) return '${s}s';
    final m = d.inMinutes;
    if (m < 60) {
      return '${m}m ${(s % 60).toString().padLeft(2, '0')}s';
    }
    return '${d.inHours}h ${(m % 60).toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final turn = session.projection.turn;
    final start = turn.startedAt;
    if (!turn.working || start == null) return const SizedBox.shrink();
    final colors = context.colors;
    final elapsed = DateTime.now().difference(start);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            size: 11,
            strokeWidth: 1.6,
            color: colors.accent,
          ),
          const SizedBox(width: 7),
          Text(
            _format(elapsed),
            style: context.typo.mono.copyWith(
              fontSize: 11.5,
              color: colors.text2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Visualize context usage as a disk that fills toward the window limit.
///
/// Color progresses from green to amber to red, and the tooltip shows the
/// percentage. [ContextUsage] supplies `percent` on a 0–100 scale.
class _ContextGauge extends StatelessWidget {
  const _ContextGauge({required this.session});
  final AgentSession session;

  @override
  Widget build(BuildContext context) {
    final percent = session.projection.controls.contextUsage?.percent;
    if (percent == null) return const SizedBox.shrink();
    final colors = context.colors;
    final fraction = (percent / 100).clamp(0.0, 1.0);
    final fill = fraction >= 0.9
        ? colors.error
        : (fraction >= 0.75 ? colors.warn : colors.accentText);
    final pct = percent.toStringAsFixed(percent < 10 ? 1 : 0);
    return Tooltip(
      tooltip: (context) =>
          TooltipContainer(child: Text('Context: $pct% of the window')),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CustomPaint(
            painter: _GaugePainter(
              fraction: fraction,
              fill: fill,
              track: colors.border2,
              ring: colors.text3,
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.fraction,
    required this.fill,
    required this.track,
    required this.ring,
  });

  final double fraction;
  final Color fill;
  final Color track;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    // Empty background.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = track
        ..style = PaintingStyle.fill,
    );

    // Fill clockwise from the top like a growing pie slice.
    if (fraction > 0) {
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: radius),
          -math.pi / 2,
          fraction * 2 * math.pi,
          false,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = fill
          ..style = PaintingStyle.fill,
      );
    }

    // Draw a more visible outline.
    canvas.drawCircle(
      center,
      radius - 0.6,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction || old.fill != fill;
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      tooltip: (context) => TooltipContainer(child: Text(tooltip)),
      child: HoverTap(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 16, color: context.colors.text3),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.streaming,
    required this.ready,
    required this.onTap,
  });

  final bool streaming;
  final bool ready;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final Color bg;
    final Color fg;
    final IconData icon;
    if (streaming) {
      bg = colors.text;
      fg = colors.bg;
      icon = Icons.stop;
    } else if (ready) {
      bg = colors.accent;
      fg = Colors.white;
      icon = Icons.arrow_upward;
    } else {
      bg = Colors.transparent;
      fg = colors.text3;
      icon = Icons.arrow_upward;
    }
    return Tooltip(
      tooltip: (context) =>
          TooltipContainer(child: Text(streaming ? 'Stop' : 'Send')),
      // A radius of 15 in a 30×30 square forms a circle. HoverTap accepts only
      // BorderRadius, so this replaces Material's CircleBorder.
      child: HoverTap(
        borderRadius: BorderRadius.circular(15),
        color: bg,
        hoverColor: bg,
        border: ready || streaming
            ? null
            : Border.all(color: colors.border2, width: 1.5),
        onTap: onTap,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(icon, size: 15, color: fg),
        ),
      ),
    );
  }
}

/// Indicate relay state and toggle it through the schema-aligned command.
///
/// Uses green for active, amber for reconnecting, and gray for offline without
/// involving the LLM or transcript.
class _RelayButton extends StatelessWidget {
  const _RelayButton({required this.session});
  final AgentSession session;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final status = session.projection.relayStatus;
    final (icon, color, tooltip) = switch (status) {
      RelayStatus.connected => (
        Icons.cell_tower,
        colors.online,
        'Relay online',
      ),
      RelayStatus.reconnecting => (
        Icons.cell_tower,
        colors.warn,
        'Relay reconnecting...',
      ),
      RelayStatus.disconnected => (
        Icons.cell_tower_outlined,
        colors.text3,
        'Relay offline',
      ),
    };
    return Tooltip(
      tooltip: (context) => TooltipContainer(child: Text(tooltip)),
      child: HoverTap(
        borderRadius: BorderRadius.circular(5),
        onTap: session.projection.isAlive
            ? () => session.sendRelayControl(
                PiControlCommand.relay(PiRelayControlAction.toggle),
              )
            : null,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Attachments from the "+" button.
// ---------------------------------------------------------------------------

const Set<String> _kImageExts = <String>{
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
};

bool _isImageName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return false;
  return _kImageExts.contains(name.substring(dot + 1).toLowerCase());
}

/// Hold one composer attachment outside the editable text.
///
/// Images retain [bytes] for preview and base64 transport; other files retain
/// only [path] for the agent to read through tools.
class _Attachment {
  _Attachment({
    required this.name,
    required this.isImage,
    this.bytes,
    this.mention,
  });

  final String name;
  final bool isImage;

  /// Retain image bytes for preview and base64 transport.
  final Uint8List? bytes;

  /// Retain the relative file reference emitted without the `@` prefix.
  final String? mention;
}

/// Warn when an attached image is invisible to the text-only model.
class _ImageModelWarning extends StatelessWidget {
  const _ImageModelWarning();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 14, color: colors.warn),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                'The current model cannot see images — switch to one with vision.',
                style: context.typo.label.copyWith(color: colors.warn),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Display image thumbnails and other file chips above the input.
class _AttachmentStrip extends StatelessWidget {
  const _AttachmentStrip({required this.attachments, required this.onRemove});

  final List<_Attachment> attachments;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    // Align(centerLeft) spans the width and pins attachments left despite the
    // composer's centered Column default.
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < attachments.length; i++)
              _AttachmentChip(
                attachment: attachments[i],
                onRemove: () => onRemove(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.attachment, required this.onRemove});

  final _Attachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final showThumb = attachment.isImage && attachment.bytes != null;

    final Widget content = showThumb
        ? ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Image.memory(
              attachment.bytes!,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
            ),
          )
        : Container(
            height: 52,
            constraints: const BoxConstraints(maxWidth: 190),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: colors.panel3,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FileTypeIcon.file(attachment.name, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    attachment.name,
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.label.copyWith(color: colors.text),
                  ),
                ),
              ],
            ),
          );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        content,
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: colors.panel,
                shape: BoxShape.circle,
                border: Border.all(color: colors.border2),
              ),
              child: Icon(Icons.close, size: 11, color: colors.text2),
            ),
          ),
        ),
      ],
    );
  }
}
