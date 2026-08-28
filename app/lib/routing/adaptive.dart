import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FlutterView;

import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Minimum logical shortest side that classifies a window as tablet-sized.
const double kTabletBreakpoint = 600.0;

/// Fixed logical width reserved for the session-list master pane.
const double kMasterPaneWidth = 360.0;

/// Minimum usable logical width reserved for the chat detail pane.
const double kMinDetailWidth = 320.0;

/// Logical width consumed by the divider between master and detail panes.
const double kPaneDividerWidth = 1.0;

/// Maximum line length for chat prose and the composer in one-pane layouts.
const double kChatReadingMeasure = 640.0;

/// Maximum width for Home filters, section headers, and session rows.
const double kHomeListMaxWidth = 560.0;

/// Width below which chat and Home headers use their compact treatments.
const double kCompactHeaderBreakpoint = 280.0;

/// Remaining height below which the chat composer sheds optional chrome.
const double kCompactComposerAvailableHeight = 280.0;

/// Remaining height above which the compact composer restores standard chrome.
const double kCompactComposerExitHeight = 360.0;

/// Whether the window has tablet semantics in either orientation.
///
/// Classify by `shortestSide` (`min(width, height)`), not width alone: a phone
/// in landscape can be wide without being tablet-sized. The rotation-invariant
/// threshold keeps phones (~360–430) phone-class and tablets (>=600)
/// tablet-class. [canUseTwoPaneLayout] separately applies the pane budget.
///
/// `MediaQuery` measures the allocated window rather than the physical device.
/// Requiring both dimensions to meet the threshold deliberately treats a short
/// landscape phone as a phone.
bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide >= kTabletBreakpoint;

/// Whether the current orientation can afford both master and detail panes.
///
/// Tablet classification remains rotation-invariant through [isWideLayout],
/// while the active orientation must also budget a usable detail beside the
/// fixed master. A tablet-sized 600–680dp window therefore stays single-pane.
bool canUseTwoPaneLayout(BuildContext context) {
  return isWideLayout(context) &&
      MediaQuery.sizeOf(context).width >=
          kMasterPaneWidth + kPaneDividerWidth + kMinDetailWidth;
}

/// Derive master-pane insets that ignore a detail-pane keyboard.
///
/// Removes the keyboard's bottom view inset, restores the stable bottom safe
/// padding from [MediaQueryData.viewPadding], and strips only the edge facing
/// the divider. Outer-edge and top safe areas remain intact.
MediaQueryData masterPaneMediaQueryData(MediaQueryData data) {
  final isolated = data
      .removeViewInsets(removeBottom: true)
      .removePadding(removeRight: true);
  return isolated.copyWith(
    padding: isolated.padding.copyWith(bottom: data.viewPadding.bottom),
  );
}

/// Restore physical window insets for a route opened from an isolated pane.
///
/// Modal builders inherit the launching Home surface's stripped MediaQuery in
/// the production shell. Reintroducing only the current platform view inset
/// lets their fields avoid the keyboard without resizing persistent Home.
MediaQueryData mediaQueryWithWindowViewInsets(BuildContext context) {
  final media = MediaQuery.of(context);
  final view = View.of(context);
  return media.copyWith(
    viewInsets: EdgeInsets.fromViewPadding(
      view.viewInsets,
      view.devicePixelRatio,
    ),
  );
}

/// Isolate only the persistent Home surface from a detail-pane keyboard.
///
/// This wrapper belongs below the master branch Navigator. Pushed routes and
/// master-owned modal sheets therefore retain the real keyboard inset while
/// Home's list stays at its stable height behind them.
class MasterPaneHomeSurface extends StatelessWidget {
  const MasterPaneHomeSurface({
    super.key,
    required this.isolateKeyboard,
    required this.child,
  });

  final bool isolateKeyboard;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isolateKeyboard) return child;
    return MediaQuery(
      data: masterPaneMediaQueryData(MediaQuery.of(context)),
      child: child,
    );
  }
}

/// Native query for whether Android currently considers the IME visible.
const MethodChannel imeVisibilityChannel = MethodChannel(
  'dev.kevoun.outpostpi/ime-visibility',
);

/// Native recovery command that asks Android to hide the window-level IME.
const MethodChannel imeRecoveryChannel = MethodChannel(
  'dev.kevoun.outpostpi/ime-recovery',
);

/// Grace period before treating a keyboard-sized inset as stale.
///
/// Four seconds is well beyond Android's normal IME close animation while
/// remaining short enough to recover the field-observed half-screen layout.
const Duration kStaleImeWatchdogDelay = Duration(seconds: 4);

/// Minimum bottom inset that can arm stale-IME recovery.
///
/// This deliberately excludes small transient/system overlays; the affected
/// Pixel Fold reports a keyboard-sized inset hundreds of logical pixels tall.
const double kStaleImeInsetThreshold = 100.0;

/// Delay between bounded stale-IME recovery attempts after the first attempt.
const Duration kStaleImeWatchdogRetryDelay = Duration(seconds: 4);

/// Maximum recovery requests for one keyboard-sized inset plateau.
const int kMaxStaleImeWatchdogAttempts = 4;

/// Dismiss a departed IME without overriding routed system-bar insets.
///
/// Flutter moves focus away when the detail branch leaves the rendered shell,
/// but that focus transition does not send `TextInput.hide`. Pixel Fold's
/// WindowManager can consequently retain the old IME inset across the posture
/// resize. Android 15+ always lays Flutter out edge-to-edge, so the routed
/// subtree must receive Flutter's platform [MediaQueryData.padding] unchanged;
/// its own [SafeArea] remains the sole owner of system-bar layout padding.
///
/// The same retention also occurs without a pane transition. Flutter 3.44 has
/// no public global `TextInput.isConnected` or IME-visibility getter: only an
/// individual [TextInputConnection.attached] is public, while [EditableText]
/// keeps that connection private. The Android host therefore exposes the
/// platform's `WindowInsets.Type.ime()` visibility through
/// [imeVisibilityChannel]. A four-second watchdog checks that independent
/// signal before sending bounded recovery requests through [imeRecoveryChannel].
/// Focus loss still reasserts immediately, and a focused [EditableText] is the
/// conservative fallback on platforms without the host channel. The timer and
/// binding/focus observers are owned by this widget.
class PaneCollapseImeDismissal extends StatefulWidget {
  const PaneCollapseImeDismissal({
    super.key,
    required this.twoPane,
    required this.child,
    this.onWatchdogRecovery,
  });

  final bool twoPane;
  final Widget child;

  /// Emit field diagnostics whenever stale-inset recovery acts.
  final VoidCallback? onWatchdogRecovery;

  @override
  State<PaneCollapseImeDismissal> createState() =>
      _PaneCollapseImeDismissalState();
}

class _PaneCollapseImeDismissalState extends State<PaneCollapseImeDismissal>
    with WidgetsBindingObserver {
  Timer? _watchdog;
  FlutterView? _view;
  int _watchdogRecoveryAttempts = 0;
  bool _hadTextInputConnection = false;

  @override
  void initState() {
    super.initState();
    _hadTextInputConnection = _hasActiveTextInputConnection();
    FocusManager.instance.addListener(_handleFocusChange);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _view = View.of(context);
    _reconcileWatchdog(MediaQuery.viewInsetsOf(context).bottom);
  }

  @override
  void didChangeMetrics() {
    _reconcileWatchdog(_windowBottomInset);
  }

  @override
  void didUpdateWidget(PaneCollapseImeDismissal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.twoPane && !widget.twoPane && _windowBottomInset > 0) {
      _scheduleHide(requireDisconnected: false, requireSinglePane: true);
    }
    _reconcileWatchdog(_windowBottomInset);
  }

  void _handleFocusChange() {
    final connected = _hasActiveTextInputConnection();
    final connectionClosed = _hadTextInputConnection && !connected;
    _hadTextInputConnection = connected;
    if (connectionClosed && _windowBottomInset > 0) {
      _scheduleHide(requireDisconnected: true, requireSinglePane: false);
    }
    _reconcileWatchdog(_windowBottomInset);
  }

  void _scheduleHide({
    required bool requireDisconnected,
    required bool requireSinglePane,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _windowBottomInset <= 0) return;
      if (requireSinglePane && widget.twoPane) return;
      if (requireDisconnected && _hasActiveTextInputConnection()) return;
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    });
  }

  void _reconcileWatchdog(double bottomInset) {
    if (!mounted) return;
    if (bottomInset < kStaleImeInsetThreshold) {
      _watchdog?.cancel();
      _watchdog = null;
      _watchdogRecoveryAttempts = 0;
      return;
    }
    if (_watchdog != null ||
        _watchdogRecoveryAttempts >= kMaxStaleImeWatchdogAttempts) {
      return;
    }
    final delay = _watchdogRecoveryAttempts == 0
        ? kStaleImeWatchdogDelay
        : kStaleImeWatchdogRetryDelay;
    _watchdog = Timer(delay, () => unawaited(_recoverStaleInset()));
  }

  Future<void> _recoverStaleInset() async {
    _watchdog = null;
    if (!mounted || _windowBottomInset < kStaleImeInsetThreshold) return;
    if (await _isImeVisible() || _hasActiveTextInputConnection()) {
      // A legitimate IME must not keep a polling timer alive. A later metrics
      // or focus transition can re-arm recovery if the input connection ends.
      if (mounted) {
        _watchdog?.cancel();
        _watchdog = null;
        _watchdogRecoveryAttempts = 0;
      }
      return;
    }
    if (!mounted || _windowBottomInset < kStaleImeInsetThreshold) return;
    _watchdogRecoveryAttempts++;
    widget.onWatchdogRecovery?.call();
    unawaited(_requestImeRecovery());
    _reconcileWatchdog(_windowBottomInset);
  }

  Future<void> _requestImeRecovery() async {
    try {
      final recovered = await imeRecoveryChannel.invokeMethod<bool>('recover');
      if (recovered == true) return;
    } on Object {
      // Tests, older hosts, and non-Android platforms do not expose the
      // window-level channel. Retain the existing input-channel backstop.
    }
    try {
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    } on Object {
      // Recovery is best effort; a host channel failure must not surface as
      // an unhandled Future error from the watchdog.
    }
  }

  double get _windowBottomInset {
    final view = _view;
    if (view == null) return 0;
    return view.viewInsets.bottom / view.devicePixelRatio;
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_handleFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<bool> _isImeVisible() async {
  try {
    return await imeVisibilityChannel.invokeMethod<bool>('isVisible') ??
        _hasActiveTextInputConnection();
  } on MissingPluginException {
    return _hasActiveTextInputConnection();
  } on PlatformException {
    return true;
  }
}

bool _hasActiveTextInputConnection() {
  final focus = FocusManager.instance.primaryFocus;
  if (focus == null || !focus.hasFocus) return false;
  final focusContext = focus.context;
  return focusContext?.widget is EditableText ||
      focusContext?.findAncestorStateOfType<EditableTextState>() != null;
}

/// Maximum single-column content width for onboarding and empty states.
const double kMaxContentWidth = 460.0;

/// Constrain modal-sheet width and height across phone and split windows.
///
/// Low-height windows center the sheet like a dialog. Scrollable sheets keep
/// the keyboard inset in their scroll padding so their final action remains
/// reachable instead of increasing the route beyond its height budget.
class AdaptiveSheetFrame extends StatelessWidget {
  const AdaptiveSheetFrame({
    super.key,
    required this.child,
    required this.maxWidth,
    this.maxHeight = 640,
    this.scrollable = true,
    this.includeKeyboardInset = false,
    this.fillHeight = false,
    this.contentKey,
  });

  final Widget child;
  final double maxWidth;
  final double maxHeight;
  final bool scrollable;
  final bool includeKeyboardInset;
  final bool fillHeight;
  final Key? contentKey;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final heightLimit = math.min(maxHeight, media.size.height * 0.88);
    final lowHeight = media.size.height < 500;
    final content = scrollable
        ? SingleChildScrollView(
            key: contentKey,
            padding: EdgeInsets.only(
              bottom: includeKeyboardInset ? media.viewInsets.bottom : 0,
            ),
            child: child,
          )
        : child;
    final heightConstrained = fillHeight
        ? SizedBox(height: heightLimit, child: content)
        : ConstrainedBox(
            constraints: BoxConstraints(maxHeight: heightLimit),
            child: content,
          );

    return SizedBox(
      height: media.size.height,
      child: SafeArea(
        top: false,
        child: Align(
          alignment: lowHeight ? Alignment.center : Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: SizedBox(width: maxWidth, child: heightConstrained),
          ),
        ),
      ),
    );
  }
}

/// Center and constrain [child] on wide screens while preserving phone layout.
///
/// Centers on both axes so it supports minimum-height empty states and
/// full-height onboarding columns with `Expanded`.
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = kMaxContentWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Hold adaptive-shell state that collapses an empty Home view to one pane.
///
/// `isZeroState` is true when no paired Pi or session can be listed or selected.
/// It defaults false so a populated tablet does not visibly transition from one
/// pane to a split during bootstrap.
class ShellLayout extends ChangeNotifier {
  bool _zeroState = false;
  bool get isZeroState => _zeroState;

  void setZeroState(bool value) {
    if (value == _zeroState) return;
    _zeroState = value;
    notifyListeners();
  }
}

/// Hold the session selected by the UI for the tablet detail pane and list.
///
/// This is distinct from the peer connected at bootstrap. It intentionally
/// starts null and is not persisted, so every app launch begins with the
/// selection placeholder until the user chooses a session.
class SelectedSession {
  const SelectedSession({
    required this.ref,
    required this.title,
    this.device = '',
    this.online = false,
  });

  final RemoteSessionRef ref;
  final String title;
  final String device;
  final bool online;

  String get epk => ref.peerEpk;
  String get roomId => ref.roomId;
  String get sessionId => ref.sessionId;
}

/// Own the current transcript-scoped selection for adaptive master-detail UI.
class SessionSelection extends ChangeNotifier {
  SelectedSession? _current;

  SelectedSession? get current => _current;

  /// Whether this canonical session is the current selection.
  ///
  /// Production callers pass [sessionId] so a Pi SDK session rotation in one
  /// relay room replaces, rather than reuses, transcript-scoped detail state.
  bool matches(String epk, String roomId, [String? sessionId]) {
    final c = _current;
    return c != null &&
        c.epk == epk &&
        c.roomId == roomId &&
        (sessionId == null || c.sessionId == sessionId);
  }

  bool matchesRef(RemoteSessionRef ref) => _current?.ref == ref;

  /// Select a transcript-scoped session and seed its detail metadata.
  ///
  /// [device] and [online] let the tablet detail pane render its AppBar before
  /// asynchronous peer/runtime reads complete. Liveness remains room-scoped,
  /// while selection follows the complete [RemoteSessionRef].
  void select(
    RemoteSessionRef ref,
    String title, [
    String device = '',
    bool online = false,
  ]) {
    final c = _current;
    if (c != null && c.ref == ref) {
      return; // no-op — avoids rebuilding the detail/master views
    }
    _current = SelectedSession(
      ref: ref,
      title: title,
      device: device,
      online: online,
    );
    notifyListeners();
  }

  void clear() {
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }
}
