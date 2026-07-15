import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:flutter/widgets.dart';

/// Minimum logical shortest side that enables the two-pane tablet layout.
const double kTabletBreakpoint = 600.0;

/// Whether the window can use the two-pane tablet layout in either orientation.
///
/// Classify by `shortestSide` (`min(width, height)`), not width alone: a phone
/// in landscape can be wide without being tablet-sized. The rotation-invariant
/// threshold keeps phones (~360–430) single-pane and tablets (>=768) split.
///
/// iPad Split View and Slide Over also collapse naturally because `MediaQuery`
/// measures the allocated window, not the physical device. Requiring both
/// dimensions to meet the threshold deliberately treats a short landscape phone
/// as a phone.
bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide >= kTabletBreakpoint;

/// Maximum single-column content width for onboarding and empty states.
const double kMaxContentWidth = 460.0;

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
