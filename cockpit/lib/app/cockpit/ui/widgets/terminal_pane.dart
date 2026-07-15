import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show HardwareKeyboard, KeyEvent;
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xterm/xterm.dart';

import 'cockpit_terminal.dart';
import 'cockpit_terminal_render.dart';
import 'terminal_link.dart';

/// Add native-style selection auto-scroll and mouse ownership to [CockpitTerminal].
///
/// xterm 4.0 extends selection only on pointer movement and never scrolls the
/// viewport during a drag. This wrapper consumes raw pointer events, scrolls via
/// [ScrollController], and extends selection from a fixed buffer anchor so its
/// start does not slip as the viewport moves. It also owns TUI mouse forwarding
/// and command-click link handling to avoid duplicate authorities.
class TerminalPane extends StatefulWidget {
  const TerminalPane({
    super.key,
    required this.terminal,
    required this.focusNode,
    required this.textStyle,
    required this.theme,
    required this.onKeyEvent,
    this.hardwareKeyboardOnly = false,
  });

  final Terminal terminal;
  final FocusNode focusNode;
  final TerminalStyle textStyle;
  final TerminalTheme theme;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;
  final bool hardwareKeyboardOnly;

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<TerminalPane>
    with SingleTickerProviderStateMixin {
  final _viewKey = GlobalKey<CockpitTerminalState>();
  final _scroll = ScrollController();
  late final _SelectionGuardController _controller;
  late final Ticker _ticker;

  /// Start auto-scroll when a drag enters this edge distance in pixels.
  static const _edgeZone = 24.0;

  /// Saturate auto-scroll speed at this distance beyond the edge.
  static const _maxOvershoot = 80.0;

  /// Cap scrolling at this many pixels per frame.
  static const _maxStep = 18.0;

  /// Treat held-button movement beyond this threshold as a drag.
  ///
  /// Smaller movement remains an xterm click or double-click.
  static const _dragSlop = 3.0;

  Offset? _downLocal; // Pointer-down in RenderTerminal coordinates.
  Offset? _pointer; // Latest pointer position in the same coordinate space.
  CellAnchor? _anchor; // Fixed selection start that follows the buffer.
  bool _selecting = false;

  /// Accumulate fractional wheel lines before forwarding to the application.
  ///
  /// Trackpads emit small frequent deltas; rounding each to one line would scroll
  /// too quickly.
  double _wheelLineAccum = 0;

  /// Track when a click or drag is being forwarded to a mouse-reporting TUI.
  ///
  /// During forwarding, TerminalPane is the sole mouse authority: it emits down,
  /// drag motion, and up while xterm's internal gesture sends nothing.
  bool _forwardingMouse = false;
  CellOffset? _tuiLastCell; // Last reported cell; motion emits only on change.

  // --- Open URLs with Cmd: pointer/highlight on hover, open on click. ---
  final _linkDetector = TerminalLinkDetector();
  MouseCursor _cursor = SystemMouseCursors.text;
  TerminalLink? _hoverLink; // Link under pointer while Cmd is held.
  TerminalHighlight? _linkHighlight; // Removable link highlight.
  Offset? _lastHoverGlobal; // Reevaluate Cmd changes without pointer movement.

  @override
  void initState() {
    super.initState();
    _controller = _SelectionGuardController();
    _ticker = createTicker(_onTick);
    // Update highlight/cursor when Cmd changes without pointer movement.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _linkHighlight?.dispose();
    _ticker.dispose();
    _anchor?.dispose();
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent _) {
    _evaluateHover(_lastHoverGlobal); // Reevaluate at the last known position.
    return false; // Observe Cmd state without consuming the event.
  }

  CockpitTerminalRender? get _render => _viewKey.currentState?.renderTerminal;

  bool get _isCmd => HardwareKeyboard.instance.isMetaPressed;

  /// Force local selection while Option is held, even when the app owns the mouse.
  ///
  /// This is the iTerm/Terminal.app-style escape hatch for copying raw text.
  bool get _isAlt => HardwareKeyboard.instance.isAltPressed;

  /// Report whether a mouse-reporting app owns clicks and selection.
  bool get _appOwnsMouse => widget.terminal.mouseMode != MouseMode.none;

  /// Reevaluate the link under global coordinates [global].
  ///
  /// Detect only while Cmd is held; otherwise selection and clicks follow normal
  /// terminal/application behavior.
  void _evaluateHover(Offset? global) {
    final r = _render;
    if (r == null || global == null) {
      _setHoverLink(null);
      return;
    }
    final link = _isCmd
        ? _linkDetector.linkAt(
            widget.terminal,
            r.getCellOffset(r.globalToLocal(global)),
          )
        : null;
    _setHoverLink(link);
  }

  void _setHoverLink(TerminalLink? link) {
    final same =
        link?.url == _hoverLink?.url &&
        link?.row == _hoverLink?.row &&
        link?.startCol == _hoverLink?.startCol;
    if (same) return;

    _linkHighlight?.dispose();
    _linkHighlight = null;
    _hoverLink = link;

    if (link != null) {
      final b = widget.terminal.buffer;
      _linkHighlight = _controller.highlight(
        p1: b.createAnchorFromOffset(CellOffset(link.startCol, link.row)),
        p2: b.createAnchorFromOffset(CellOffset(link.endCol, link.row)),
        color: widget.theme.selection,
      );
    }
    setState(() {
      _cursor = link != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.text;
    });
  }

  void _openLink(String url) {
    final raw = url.startsWith('www.') ? 'https://$url' : url;
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.hasScheme) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    // Desktop drag selection requires a mouse/trackpad button, not touch.
    if (e.kind == PointerDeviceKind.touch) return;
    if ((e.buttons & kPrimaryButton) == 0) return;
    // Cmd-click opens a link rather than starting selection.
    if (_isCmd) return;
    final r = _render;
    if (r == null) return;
    // Forward click and drag when Claude/Vim owns the mouse so it selects and
    // scrolls itself. Holding Option overrides this for local raw-text selection.
    if (_appOwnsMouse && !_isAlt) {
      final cell = r.getCellOffset(r.globalToLocal(e.position));
      _forwardingMouse = true;
      _tuiLastCell = cell;
      widget.terminal.mouseInput(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        cell,
      );
      return;
    }
    _downLocal = r.globalToLocal(e.position);
    _pointer = _downLocal;
    _selecting = false;
  }

  void _onPointerMove(PointerMoveEvent e) {
    if ((e.buttons & kPrimaryButton) == 0) return;
    final r = _render;
    if (r == null) return;
    // While forwarding, emit held-button motion on each cell change so dragging
    // becomes selection inside Claude/Vim.
    if (_forwardingMouse) {
      final cell = r.getCellOffset(r.globalToLocal(e.position));
      if (_tuiLastCell != null &&
          cell.x == _tuiLastCell!.x &&
          cell.y == _tuiLastCell!.y) {
        return;
      }
      _tuiLastCell = cell;
      _sendMouseMotion(cell);
      return;
    }
    final down = _downLocal;
    if (down == null) return;
    final local = r.globalToLocal(e.position);
    _pointer = local;
    if (!_selecting) {
      if ((local - down).distance < _dragSlop) return;
      _beginSelecting(r, down);
    }
    _extendSelection(r);
    _syncAutoScroll(r);
  }

  void _onPointerUp(PointerUpEvent e) {
    // End TUI forwarding by releasing the button at the current cell.
    if (_forwardingMouse) {
      final r = _render;
      if (r != null) {
        final cell = r.getCellOffset(r.globalToLocal(e.position));
        widget.terminal.mouseInput(
          TerminalMouseButton.left,
          TerminalMouseButtonState.up,
          cell,
        );
      }
      _forwardingMouse = false;
      _tuiLastCell = null;
      return;
    }
    // Open a link in the browser on Cmd-click without dragging.
    if (_isCmd && !_selecting && _hoverLink != null) {
      _openLink(_hoverLink!.url);
    }
    _finishSelecting();
  }

  /// Forward held-button pointer motion to the TUI.
  ///
  /// xterm's `mouseInput` exposes only down/up, while mouse modes 1002/1003 encode
  /// motion by adding bit 32 to the button id. Build that sequence here and send
  /// it through the same `onOutput`, only for modes that expect motion.
  void _sendMouseMotion(CellOffset cell) {
    final mode = widget.terminal.mouseMode;
    if (mode != MouseMode.upDownScrollDrag &&
        mode != MouseMode.upDownScrollMove) {
      return;
    }
    final out = widget.terminal.onOutput;
    if (out == null) return;
    const motionLeft = 0 + 32; // Left button (0) plus motion bit (32).
    final x = cell.x + 1; // The protocol is one-based.
    final y = cell.y + 1;
    final seq = switch (widget.terminal.mouseReportMode) {
      MouseReportMode.sgr => '\x1b[<$motionLeft;$x;${y}M',
      MouseReportMode.urxvt => '\x1b[${32 + motionLeft};$x;${y}M',
      MouseReportMode.normal || MouseReportMode.utf =>
        '\x1b[M${String.fromCharCode(32 + motionLeft)}'
            '${String.fromCharCode(32 + x)}${String.fromCharCode(32 + y + 1)}',
    };
    out(seq);
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final term = widget.terminal;
    // An application owns scrolling when it declares scroll mouse reporting.
    // Claude/Vim then repaints cells while scrolling, so anchored selection cannot
    // follow changed text and must be cleared. The same applies to a plain alt
    // buffer such as less. In normal buffer without reporting, local scrollback
    // moves and the selection follows, so preserve it.
    final appOwnsScroll = term.mouseMode.reportScroll;
    final alt = term.buffer.isAltBuffer;
    if ((appOwnsScroll || alt) && _controller.selection != null) {
      _controller.clearSelection();
    }
    // Forward wheel input in normal buffer because CockpitTerminal's Scrollable
    // is NeverScrollable when the app owns scrolling. In alt buffer, xterm's
    // TerminalScrollGestureHandler forwards it, so do not duplicate.
    if (appOwnsScroll && !alt) {
      final r = _render;
      if (r == null) return;
      final lineHeight = r.lineHeight;
      if (lineHeight <= 0) return;
      _wheelLineAccum += e.scrollDelta.dy / lineHeight;
      final steps = _wheelLineAccum.truncate();
      if (steps == 0) return;
      _wheelLineAccum -= steps;
      final cell = r.getCellOffset(r.globalToLocal(e.position));
      final button = steps < 0
          ? TerminalMouseButton.wheelUp
          : TerminalMouseButton.wheelDown;
      for (var i = 0; i < steps.abs(); i++) {
        term.mouseInput(button, TerminalMouseButtonState.down, cell);
      }
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (_forwardingMouse) {
      final r = _render;
      final cell =
          r?.getCellOffset(r.globalToLocal(e.position)) ?? _tuiLastCell;
      if (cell != null) {
        widget.terminal.mouseInput(
          TerminalMouseButton.left,
          TerminalMouseButtonState.up,
          cell,
        );
      }
      _forwardingMouse = false;
      _tuiLastCell = null;
    }
    _finishSelecting();
  }

  void _beginSelecting(CockpitTerminalRender r, Offset down) {
    _anchor?.dispose();
    _anchor = widget.terminal.buffer.createAnchorFromOffset(
      r.getCellOffset(down),
    );
    _selecting = true;
    // Ignore xterm's internal selection from here and own it for the entire drag.
    _controller.suppressGestureSelection = true;
  }

  /// Extend selection from the fixed anchor to the pointer.
  ///
  /// Clamp Y within the viewport so an out-of-bounds pointer follows the nearest
  /// visible line as scrolling advances through the buffer.
  void _extendSelection(CockpitTerminalRender r) {
    final anchor = _anchor;
    final p = _pointer;
    if (anchor == null || p == null || !anchor.attached) return;
    final h = r.size.height;
    final clampedY = p.dy.clamp(0.0, h - 1.0);
    final from = anchor.offset;
    var to = r.getCellOffset(Offset(p.dx, clampedY));
    // Match xterm by including the cell under a forward drag, avoiding a
    // one-cell-short selection.
    if (to.x >= from.x) {
      to = CellOffset(to.x + 1, to.y);
    }
    final buffer = widget.terminal.buffer;
    _controller.setSelectionFromGuard(
      buffer.createAnchorFromOffset(from),
      buffer.createAnchorFromOffset(to),
    );
  }

  void _syncAutoScroll(CockpitTerminalRender r) {
    if (_overshoot(r) == 0) {
      if (_ticker.isActive) _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  /// Measure pointer distance beyond the edge zone.
  ///
  /// Negative scrolls up, positive scrolls down, and zero disables auto-scroll.
  double _overshoot(CockpitTerminalRender r) {
    final p = _pointer;
    if (p == null) return 0;
    final h = r.size.height;
    if (p.dy < _edgeZone) return p.dy - _edgeZone;
    if (p.dy > h - _edgeZone) return p.dy - (h - _edgeZone);
    return 0;
  }

  void _onTick(Duration _) {
    final r = _render;
    if (r == null || !_selecting) {
      _ticker.stop();
      return;
    }
    final over = _overshoot(r);
    if (over == 0) {
      _ticker.stop();
      return;
    }
    if (_scroll.hasClients) {
      final pos = _scroll.position;
      final frac = (over.abs() / _maxOvershoot).clamp(0.0, 1.0);
      final step = over.sign * frac * _maxStep;
      final next = (pos.pixels + step).clamp(
        pos.minScrollExtent,
        pos.maxScrollExtent,
      );
      if (next != pos.pixels) {
        _scroll.jumpTo(next);
      }
    }
    // Re-extend selection to the new visible edge after viewport scrolling.
    _extendSelection(r);
  }

  void _finishSelecting() {
    if (_ticker.isActive) _ticker.stop();
    if (_selecting) {
      _selecting = false;
      _controller.suppressGestureSelection = false;
    }
    _anchor?.dispose();
    _anchor = null;
    _downLocal = null;
    _pointer = null;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _cursor,
      onHover: (e) {
        _lastHoverGlobal = e.position;
        _evaluateHover(e.position);
      },
      onExit: (_) {
        _lastHoverGlobal = null;
        _setHoverLink(null);
      },
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        onPointerSignal: _onPointerSignal,
        // The outer MouseRegion chooses a hand over Cmd-links or an I-beam;
        // CockpitTerminal defers its cursor here.
        child: CockpitTerminal(
          widget.terminal,
          key: _viewKey,
          controller: _controller,
          scrollController: _scroll,
          focusNode: widget.focusNode,
          hardwareKeyboardOnly: widget.hardwareKeyboardOnly,
          onKeyEvent: (_, event) => widget.onKeyEvent(event),
          theme: widget.theme,
          textStyle: widget.textStyle,
          mouseCursor: MouseCursor.defer,
        ),
      ),
    );
  }
}

/// Suppress xterm's internal selection writes while [TerminalPane] owns selection.
///
/// During auto-scroll drag, xterm recalculates from a fixed pixel without scroll
/// compensation. Ignoring those writes prevents conflict with the anchored
/// selection and keeps its start from jumping.
class _SelectionGuardController extends TerminalController {
  bool suppressGestureSelection = false;
  bool _fromGuard = false;

  void setSelectionFromGuard(
    CellAnchor base,
    CellAnchor extent, {
    SelectionMode? mode,
  }) {
    _fromGuard = true;
    setSelection(base, extent, mode: mode);
    _fromGuard = false;
  }

  @override
  void setSelection(CellAnchor base, CellAnchor extent, {SelectionMode? mode}) {
    if (suppressGestureSelection && !_fromGuard) {
      // xterm transfers anchor ownership expecting consumption; release ignored
      // anchors to avoid leaks.
      base.dispose();
      extent.dispose();
      return;
    }
    super.setSelection(base, extent, mode: mode);
  }
}
