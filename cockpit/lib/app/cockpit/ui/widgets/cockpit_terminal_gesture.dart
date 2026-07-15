// Fork of xterm's `TerminalGestureHandler`
// (`src/ui/gesture/gesture_handler.dart`). The original binds `terminalView` to
// xterm's `TerminalViewState`; Cockpit needs [CockpitTerminalState] to reach
// [CockpitTerminalRender]. Tap, drag, double-tap selection, and terminal mouse
// logic remain identical. Reuse the view-agnostic `TerminalGestureDetector`.
//
// ignore_for_file: implementation_imports
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter/widgets.dart';
import 'package:xterm/src/core/mouse/button.dart';
import 'package:xterm/src/core/mouse/button_state.dart';
import 'package:xterm/src/core/mouse/mode.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/gesture/gesture_detector.dart';

import 'cockpit_terminal.dart';
import 'cockpit_terminal_render.dart';

/// Adapt xterm's gesture contract to [CockpitTerminalState] and its renderer.
///
/// Keeps xterm selection behavior while allowing [TerminalPane] to remain the
/// sole authority for raw mouse forwarding and selection auto-scroll.
class CockpitTerminalGestureHandler extends StatefulWidget {
  const CockpitTerminalGestureHandler({
    super.key,
    required this.terminalView,
    required this.terminalController,
    this.child,
    this.onTapUp,
    this.onSingleTapUp,
    this.onTapDown,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.onTertiaryTapDown,
    this.onTertiaryTapUp,
    this.readOnly = false,
  });

  final CockpitTerminalState terminalView;

  final TerminalController terminalController;

  final Widget? child;

  final GestureTapUpCallback? onTapUp;

  final GestureTapUpCallback? onSingleTapUp;

  final GestureTapDownCallback? onTapDown;

  final GestureTapDownCallback? onSecondaryTapDown;

  final GestureTapUpCallback? onSecondaryTapUp;

  final GestureTapDownCallback? onTertiaryTapDown;

  final GestureTapUpCallback? onTertiaryTapUp;

  final bool readOnly;

  @override
  State<CockpitTerminalGestureHandler> createState() =>
      _CockpitTerminalGestureHandlerState();
}

class _CockpitTerminalGestureHandlerState
    extends State<CockpitTerminalGestureHandler> {
  CockpitTerminalState get terminalView => widget.terminalView;

  CockpitTerminalRender get renderTerminal => terminalView.renderTerminal;

  DragStartDetails? _lastDragStartDetails;

  LongPressStartDetails? _lastLongPressStartDetails;

  @override
  Widget build(BuildContext context) {
    return TerminalGestureDetector(
      onTapUp: widget.onTapUp,
      onSingleTapUp: onSingleTapUp,
      onTapDown: onTapDown,
      onSecondaryTapDown: onSecondaryTapDown,
      onSecondaryTapUp: onSecondaryTapUp,
      onTertiaryTapDown: onSecondaryTapDown,
      onTertiaryTapUp: onSecondaryTapUp,
      onLongPressStart: onLongPressStart,
      onLongPressMoveUpdate: onLongPressMoveUpdate,
      onDragStart: onDragStart,
      onDragUpdate: onDragUpdate,
      onDoubleTapDown: onDoubleTapDown,
      child: widget.child,
    );
  }

  /// Allow local renderer selection only when the application does not own mouse input.
  ///
  /// Holding Option is the iTerm-style escape hatch for copying raw text. When
  /// applications such as Claude or Vim own the mouse, their selection remains
  /// authoritative and Cockpit does not paint a second selection.
  bool get _localSelectionAllowed =>
      terminalView.widget.terminal.mouseMode == MouseMode.none ||
      HardwareKeyboard.instance.isAltPressed;

  // TerminalPane is the sole authority for forwarding raw down/motion/up events
  // to the TUI. Do not forward taps here or the application receives duplicates;
  // retain only the focus callback on onTapDown.
  static const bool _shouldSendTapEvent = false;

  void _tapDown(
    GestureTapDownCallback? callback,
    TapDownDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.down,
        details.localPosition,
      );
    }
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void _tapUp(
    GestureTapUpCallback? callback,
    TapUpDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.up,
        details.localPosition,
      );
    }
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void onTapDown(TapDownDetails details) {
    // onTapDown is special, as it will always call the supplied callback.
    // The CockpitTerminal depends on it to bring the terminal into focus.
    _tapDown(
      widget.onTapDown,
      details,
      TerminalMouseButton.left,
      forceCallback: true,
    );
  }

  void onSingleTapUp(TapUpDetails details) {
    _tapUp(widget.onSingleTapUp, details, TerminalMouseButton.left);
  }

  void onSecondaryTapDown(TapDownDetails details) {
    _tapDown(widget.onSecondaryTapDown, details, TerminalMouseButton.right);
  }

  void onSecondaryTapUp(TapUpDetails details) {
    _tapUp(widget.onSecondaryTapUp, details, TerminalMouseButton.right);
  }

  void onTertiaryTapDown(TapDownDetails details) {
    _tapDown(widget.onTertiaryTapDown, details, TerminalMouseButton.middle);
  }

  void onTertiaryTapUp(TapUpDetails details) {
    _tapUp(widget.onTertiaryTapUp, details, TerminalMouseButton.right);
  }

  void onDoubleTapDown(TapDownDetails details) {
    // When the application owns the mouse, forwarded double taps drive its word
    // selection; do not paint a local selection over it.
    if (!_localSelectionAllowed) return;
    renderTerminal.selectWord(details.localPosition);
  }

  void onLongPressStart(LongPressStartDetails details) {
    if (!_localSelectionAllowed) return;
    _lastLongPressStartDetails = details;
    renderTerminal.selectWord(details.localPosition);
  }

  void onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_localSelectionAllowed) return;
    renderTerminal.selectWord(
      _lastLongPressStartDetails!.localPosition,
      details.localPosition,
    );
  }

  void onDragStart(DragStartDetails details) {
    if (!_localSelectionAllowed) return;
    _lastDragStartDetails = details;

    details.kind == PointerDeviceKind.mouse
        ? renderTerminal.selectCharacters(details.localPosition)
        : renderTerminal.selectWord(details.localPosition);
  }

  void onDragUpdate(DragUpdateDetails details) {
    if (!_localSelectionAllowed || _lastDragStartDetails == null) return;
    renderTerminal.selectCharacters(
      _lastDragStartDetails!.localPosition,
      details.localPosition,
    );
  }
}
