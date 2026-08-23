import 'dart:async';

import 'package:app/data/preferences/preferences.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/chat/quick_actions/widgets/quick_actions_sheet.dart';
import 'package:app/ui/chat/attachment/states/attachment_state.dart';
import 'package:app/ui/chat/attachment/viewmodels/attachment_viewmodel.dart';
import 'package:app/ui/chat/states/chat_state.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:app/ui/chat/voice/viewmodels/voice_input_viewmodel.dart';
import 'package:app/ui/chat/widgets/attach_sheet.dart';
import 'package:app/ui/chat/widgets/input_bar.dart';
import 'package:app/ui/chat/widgets/message_bubble.dart';
import 'package:app/ui/chat/widgets/streaming_bubble.dart';
import 'package:app/ui/chat/widgets/tool_request_card.dart';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

class ChatPage extends StatefulWidget {
  /// Plan/24-fix-title: optional title hint passed via `go_router`
  /// `extra` from the Home tile. Used as the peer-label fallback in
  /// the AppBar so the user sees the right name *immediately* on
  /// navigation, instead of "—" / "Outpost-Pi" until the PeerRecord
  /// is loaded by the ViewModel and the first `room_meta_updated`
  /// arrives.
  final String? initialTitle;

  /// Plan/32g — the paired-device (Mac) label Home already knows, passed via
  /// `extra` / [SessionSelection]. Drives the AppBar's line 2 immediately so
  /// it never flickers empty/room-title while the PeerRecord loads async.
  /// When the PeerRecord arrives it resolves to the same string, so there's no
  /// visible change.
  final String? initialDevice;

  /// Plan/32g — the live state of the tile Home tapped (its green dot). Seeds
  /// the AppBar status dot so it doesn't flash "reconnecting" before the VM
  /// reads the real runtime. Superseded by the live signal once it resolves
  /// ([ChatViewModel.connectionResolved]).
  final bool initialOnline;

  /// Plan/tablet — `false` when the chat is embedded as the tablet's
  /// detail pane (no navigation stack to pop back to). Hides the back
  /// arrow; defaults to `true` for the phone full-screen route.
  final bool showBack;

  const ChatPage({
    super.key,
    this.initialTitle,
    this.initialDevice,
    this.initialOnline = false,
    this.showBack = true,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  bool? _compactComposer;

  String? get initialTitle => widget.initialTitle;
  String? get initialDevice => widget.initialDevice;
  bool get initialOnline => widget.initialOnline;
  bool get showBack => widget.showBack;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(context.read<ChatViewModel>().refreshOnResume());
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ChatViewModel>();
    final state = vm.state;
    final media = MediaQuery.of(context);
    final compactComposer = _resolveCompactComposer(
      media.size.height - media.viewInsets.bottom,
    );

    return Scaffold(
      backgroundColor: context.colors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context, state),
            // Pairing revocation is the only banner kept — it's a hard
            // failure (can't proceed without re-pairing), red, with an
            // explicit action. Plain offline / Pi-gone / presence-off
            // banners were removed: the AppBar status line already
            // surfaces those, and stacking duplicates noise the surface.
            if (state is ChatReady && state.pairingRevoked)
              _RevokedBanner(onRePair: () => context.go('/pair')),
            if (state is ChatReady &&
                state.persistenceWarning != null &&
                !state.pairingRevoked)
              _PersistenceWarningBanner(
                message: state.persistenceWarning!,
                onRetry: vm.retryPersistenceSync,
              ),
            Expanded(child: _buildBody(context, state, vm)),
            _buildInput(context, state, vm, compactHeight: compactComposer),
          ],
        ),
      ),
    );
  }

  /// Apply separate entry and exit bounds across animated keyboard insets.
  bool _resolveCompactComposer(double availableHeight) {
    final compact = _compactComposer;
    if (compact == null) {
      return _compactComposer =
          availableHeight < kCompactComposerAvailableHeight;
    }
    if (compact) {
      if (availableHeight > kCompactComposerExitHeight) {
        _compactComposer = false;
      }
    } else if (availableHeight < kCompactComposerAvailableHeight) {
      _compactComposer = true;
    }
    return _compactComposer!;
  }

  Widget _buildTopBar(BuildContext context, ChatState state) {
    // Plan-17 follow-up — two-line AppBar:
    //   Line 1: ROOM name (cwd basename / room.name / fallback).
    //   Line 2: peer (Mac nickname or sessionName) + presence dot.
    // Transport, turn, and steering labels come from ChatReady.status.
    final colors = context.colors;
    final vm = context.watch<ChatViewModel>();
    final peer = vm.activePeer;
    final room = vm.activeRoom;
    // The navigation hint is used only until the first runtime snapshot. Once
    // resolved, every label/control consumes the ViewModel's composed status.
    final projectedStatus = state is ChatReady
        ? state.status
        : vm.statusProjection;
    final status = !vm.connectionResolved && initialOnline
        ? ChatStatusProjection(
            transport: const ChatTransportOnline(roomId: 'main'),
            turn: projectedStatus.turn,
            steering: projectedStatus.steering,
          )
        : projectedStatus;

    // Plan/24-fix-title: pass the navigation hint into the helpers so
    // either line of the AppBar (room or peer) shows it instead of
    // the generic placeholders when the ViewModel hasn't finished
    // bootstrapping yet.
    final roomName = _roomDisplayName(room, state, initialTitle);
    // Plan/32g — line 2 (device) falls back to `initialDevice` (the Mac name
    // Home passed), NOT `initialTitle` (the room name) — so it shows the right
    // device from frame 1 and doesn't flip when the PeerRecord loads.
    final peerLabel = _peerDisplayName(peer, initialDevice);
    final compact = MediaQuery.sizeOf(context).width < kCompactHeaderBreakpoint;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          if (showBack)
            IconButton(
              icon: Icon(LucideIcons.chevronLeft, size: 18, color: colors.text),
              tooltip: 'Back',
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/home'),
            )
          else
            const SizedBox(width: 16),
          Expanded(
            key: Key(compact ? 'chat-header-compact' : 'chat-header-standard'),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _truncate(roomName, 28),
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: kMonoFamily,
                    fontSize: 13,
                    color: colors.text,
                    letterSpacing: -0.2,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                if (compact)
                  _ChatStatusIndicator(status: status, compact: true)
                else
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _truncate(peerLabel, 24),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: kMonoFamily,
                            fontSize: 12,
                            color: colors.muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _ChatStatusIndicator(status: status),
                    ],
                  ),
              ],
            ),
          ),
          // Plan/32g follow-up: ALWAYS render the info button. Gating it on the
          // async PeerRecord made it pop in on load → an AppBar layout shift
          // (the flicker the user saw). Title + device already render from the
          // nav hints, so the bar is stable from frame 1. The dialog needs the
          // loaded PeerRecord; we read it at tap time (loaded within ms of
          // mount for the connection) and no-op in the unlikely pre-load tap.
          IconButton(
            icon: Icon(LucideIcons.info, size: 18, color: colors.muted2),
            tooltip: 'Session info',
            onPressed: () {
              final p = vm.activePeer;
              if (p != null) {
                _showSessionInfo(context, p, vm.activeRoom, roomName);
              }
            },
          ),
        ],
      ),
    );
  }

  /// Session details dialog — surfaced from the AppBar info action.
  /// Shows the human name, the Pi-side path (cwd), the owning device,
  /// plus model/room/paired-date when known.
  static Future<void> _showSessionInfo(
    BuildContext context,
    PeerRecord peer,
    RoomInfo? room,
    String name,
  ) {
    final owner = (peer.nickname?.isNotEmpty ?? false)
        ? peer.nickname!
        : peer.sessionName.isNotEmpty
        ? peer.sessionName
        : peer.remoteEpk.substring(0, 8);
    final model = room?.model;
    final paired = peer.pairedAt.contains('T')
        ? peer.pairedAt.split('T').first
        : peer.pairedAt;
    return showDialog<void>(
      context: context,
      builder: (dCtx) {
        final colors = dCtx.colors;
        return AlertDialog(
          backgroundColor: colors.bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: colors.border),
          ),
          title: Text(
            'Session info',
            style: TextStyle(
              fontFamily: kMonoFamily,
              fontSize: 15,
              color: colors.text,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(label: 'Name', value: name),
              _InfoRow(label: 'Path', value: room?.cwd ?? '—'),
              _InfoRow(label: 'Owner', value: owner),
              if (model != null && model.isNotEmpty)
                _InfoRow(label: 'Model', value: model),
              _InfoRow(label: 'Room', value: room?.roomId ?? '—'),
              _InfoRow(label: 'Paired', value: paired),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(),
              child: Text(
                'Close',
                style: TextStyle(fontFamily: kMonoFamily, color: colors.accent),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _roomDisplayName(
    RoomInfo? room,
    ChatState state,
    String? initialTitle,
  ) {
    if (room != null) {
      if (room.name != null && room.name!.isNotEmpty) return room.name!;
      final cwd = room.cwd;
      if (cwd != null && cwd.isNotEmpty) {
        final segs = cwd.split('/').where((s) => s.isNotEmpty).toList();
        if (segs.isNotEmpty) return segs.last;
      }
    }
    if (state is ChatReady && state.messages.isNotEmpty) {
      return _inferSessionName(state.messages);
    }
    // Plan/24-fix-title: Home knows the peer label before /chat
    // mounts; use it instead of the generic 'Outpost-Pi' placeholder
    // while we wait for the first room_meta_updated to populate
    // `room.name`.
    if (initialTitle != null && initialTitle.isNotEmpty) return initialTitle;
    return 'Outpost-Pi';
  }

  static String _peerDisplayName(PeerRecord? peer, String? fallback) {
    if (peer == null) {
      // Plan/32g: while the ViewModel hasn't loaded the PeerRecord yet, fall
      // back to the device label Home passed (initialDevice) — same value the
      // PeerRecord resolves to, so no flicker on load.
      if (fallback != null && fallback.isNotEmpty) return fallback;
      return '—';
    }
    if (peer.nickname != null && peer.nickname!.isNotEmpty) {
      return peer.nickname!;
    }
    if (peer.sessionName.isNotEmpty) return peer.sessionName;
    return peer.remoteEpk.substring(0, 8);
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1)}…';

  Widget _buildBody(BuildContext context, ChatState state, ChatViewModel vm) {
    final hideToolCalls = context.watch<Preferences>().hideToolCalls;
    return switch (state) {
      // Edge case: opened /chat without a peer (e.g. peer revoked while
      // user was here). The chat is not the place to pair — render
      // a minimal empty state without an action. User navigates back
      // and uses Home / Settings → pairing.
      ChatNoPeer() => const _EmptyState(
        icon: LucideIcons.messageCircle,
        message: 'No active device',
      ),
      ChatConnecting() => const _EmptyState(
        icon: LucideIcons.refreshCw,
        message: 'Connecting…',
      ),
      ChatInitializationFailed(:final message) => _EmptyState(
        icon: LucideIcons.circleAlert,
        message: message,
        actionLabel: 'Retry',
        onAction: vm.initialize,
      ),
      ChatFatalError(:final message) => _EmptyState(
        icon: LucideIcons.circleAlert,
        message: message,
        actionLabel: 'Re-pair',
        onAction: () => context.go('/pair'),
      ),
      ChatReady(:final messages, :final streaming) => () {
        final visible = hideToolCalls
            ? messages.where((m) => m is! ToolEvent).toList()
            : messages;
        // Empty body → the default placeholder (Pi brand icon + "Nothing
        // here"), shown whenever there's nothing to render — including while
        // reconnecting (the reconnect handshake never swaps the body).
        if (visible.isEmpty && streaming == null) {
          return const _EmptyState(
            icon: LucideIcons.terminal,
            message: 'Nothing here',
          );
        }
        return _MessageList(
          messages: visible,
          streaming: streaming,
          isReconnecting: state.status.transport is! ChatTransportOnline,
          onDecide: (id, decision) => vm.approveTool(id, decision),
        );
      }(),
    };
  }

  Widget _buildInput(
    BuildContext context,
    ChatState state,
    ChatViewModel vm, {
    required bool compactHeight,
  }) {
    final isReady = state is ChatReady;
    final isOffline = isReady && state.isOffline;
    final isRevoked = isReady && state.pairingRevoked;
    final isPeerOffline = isReady && state.peerOfflineReason != null;
    // Stop follows the whole active turn, while transport independently gates
    // whether the cancel command can be sent.
    final isWorking = isReady && state.status.turn.working;
    final cancelId = isReady && state.status.canCancel
        ? state.status.turn.cancelTargetId
        : null;
    // Quick actions need an open channel to dispatch — only offer the
    // entry point when the chat input itself is enabled. Hiding the
    // ⚙ button on offline avoids a tap that would just throw inside
    // the sheet.
    final actionsEnabled =
        isReady && !isOffline && !isRevoked && !isPeerOffline;

    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        key: const Key('chat-composer-reading-column'),
        constraints: const BoxConstraints(maxWidth: kChatReadingMeasure),
        child: InputBar(
          disabled: !isReady || isOffline || isRevoked || isPeerOffline,
          streaming: isWorking,
          compactHeight: compactHeight,
          onCancel: cancelId != null ? () => vm.cancel(cancelId) : null,
          onOpenQuickActions: actionsEnabled
              ? () => showQuickActionsSheet(context)
              : null,
          queuedText: isReady ? state.queuedText : null,
          onSetQueued: vm.setQueuedMessage,
          onClearQueued: vm.clearQueuedMessage,
          // Plan/29 — hold-to-talk voice input. The VM is route-scoped (bound in
          // app_router alongside ChatViewModel); InputBar listens to it directly,
          // so a read() is enough here.
          voice: context.read<VoiceInputViewModel>(),
          onVoiceHint: (hint) => _handleVoiceHint(context, hint),
          // Plan/30 — image attachments. takeImageForSend() reads + clears the
          // attached image so the inline image rides along with the (optionally
          // empty) caption. Attach-button gating by vision / already-attached is
          // internal to InputBar; the host only gates by channel availability.
          attachment: context.read<AttachmentViewModel>(),
          onOpenAttach: actionsEnabled
              ? () => _openAttach(context, context.read<AttachmentViewModel>())
              : null,
          onSend: (text) {
            final image = context
                .read<AttachmentViewModel>()
                .takeImageForSend();
            vm.sendMessage(text, image: image);
          },
        ),
      ),
    );
  }

  /// Open the Camera/Gallery sheet and drive the picker.
  ///
  /// Resolves the messenger only after the async picker completes and the
  /// originating context is still mounted.
  static Future<void> _openAttach(
    BuildContext context,
    AttachmentViewModel vm,
  ) async {
    final source = await showAttachSheet(context);
    if (source == null) return;
    AttachHint? hint;
    final sub = vm.hints.listen((h) => hint = h);
    switch (source) {
      case AttachSource.camera:
        await vm.pickFromCamera();
      case AttachSource.gallery:
        await vm.pickFromGallery();
    }
    await Future<void>.delayed(Duration.zero); // flush the hint microtask
    await sub.cancel();
    if (!context.mounted || hint == null) return;
    _handleAttachHint(ScaffoldMessenger.of(context), hint!);
  }

  static void _handleAttachHint(
    ScaffoldMessengerState messenger,
    AttachHint hint,
  ) {
    messenger.hideCurrentSnackBar();
    switch (hint) {
      case AttachHint.cameraPermissionDenied:
        messenger.showSnackBar(
          SnackBar(
            content: const Text(
              'Camera access is off — enable it in Settings to attach a photo.',
            ),
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Settings',
              onPressed: AppSettings.openAppSettings,
            ),
          ),
        );
      case AttachHint.pickFailed:
        messenger.showSnackBar(
          const SnackBar(
            content: Text("Couldn't attach that image."),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  /// Surfaces the InputBar's voice hints (decision #10 permission path +
  /// the "hold to talk" nudge) as snackbars. Captures the messenger up front
  /// so the settings deep-link is safe across the async permission round-trip.
  static void _handleVoiceHint(BuildContext context, VoiceHint hint) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    switch (hint) {
      case VoiceHint.holdToTalk:
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Hold the mic to talk'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case VoiceHint.permissionDenied:
        messenger.showSnackBar(
          SnackBar(
            content: const Text(
              'Microphone access is off — enable it in Settings to dictate.',
            ),
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Settings',
              onPressed: AppSettings.openAppSettings,
            ),
          ),
        );
    }
  }

  static String _inferSessionName(List<ChatMessage> msgs) {
    for (final m in msgs) {
      if (m is UserMsg) return m.text.substring(0, m.text.length.clamp(0, 32));
    }
    return 'Outpost-Pi';
  }
}

// ---------------------------------------------------------------------------

/// Render transport health, agent phase, and steering as independent labels.
class _ChatStatusIndicator extends StatelessWidget {
  const _ChatStatusIndicator({required this.status, this.compact = false});

  final ChatStatusProjection status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (transportLabel, transportColor) = switch (status.transport) {
      ChatTransportOnline() => ('online', colors.success),
      ChatTransportRetrying() => ('reconnecting…', colors.warning),
      ChatTransportOffline() => ('offline', colors.muted),
    };
    final (agentLabel, agentColor) = switch (status.turn.status) {
      AppTurnStatus.idle => (null, colors.muted),
      AppTurnStatus.working => ('working…', colors.working),
      AppTurnStatus.awaitingTool => ('waiting…', colors.warning),
      AppTurnStatus.streaming => ('streaming…', colors.working),
      AppTurnStatus.done => ('done', colors.success),
      AppTurnStatus.error => ('error', colors.error),
      AppTurnStatus.stale => ('stale', colors.muted),
    };
    final steeringLabel = status.steering is SteeringPending
        ? 'steering…'
        : null;

    Text label(String text, Color color) => Text(
      text,
      key: compact ? const Key('chat-status-priority-label') : null,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontFamily: kMonoFamily, fontSize: 12, color: color),
    );

    final (priorityLabel, priorityColor) = steeringLabel != null
        ? (steeringLabel, colors.muted2)
        : agentLabel != null
        ? (agentLabel, agentColor)
        : (transportLabel, transportColor);

    return Row(
      key: compact ? const Key('chat-status-compact') : null,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: transportColor,
          ),
        ),
        const SizedBox(width: 4),
        if (compact)
          Flexible(child: label(priorityLabel, priorityColor))
        else ...[
          label(transportLabel, transportColor),
          if (agentLabel != null) ...[
            const SizedBox(width: 6),
            label(agentLabel, agentColor),
          ],
          if (steeringLabel != null) ...[
            const SizedBox(width: 6),
            label(steeringLabel, colors.muted2),
          ],
        ],
      ],
    );
  }
}

class _MessageList extends StatefulWidget {
  final List<ChatMessage> messages;
  final StreamingMessage? streaming;
  final bool isReconnecting;
  final void Function(String, ApproveDecision) onDecide;

  const _MessageList({
    required this.messages,
    required this.streaming,
    required this.isReconnecting,
    required this.onDecide,
  });

  @override
  State<_MessageList> createState() => _MessageListState();
}

/// Keep transcript identity and the user's reading position stable across replay.
///
/// Bottom readers remain pinned to the newest row. Readers higher in history
/// retain the first visible message and its pixel offset while canonical
/// backfill inserts older rows. A bounded reconnect chip makes the update read
/// as continuation rather than apparent reordering.
class _MessageListState extends State<_MessageList> {
  final _controller = ScrollController();
  final _viewportKey = GlobalKey();
  final Map<String, GlobalKey> _messageKeys = {};
  Timer? _continuationTimer;
  _ViewportAnchor? _pendingAnchor;
  var _wasAtBottom = true;
  var _awaitingReconnectHydration = false;
  var _showContinuation = false;

  @override
  void initState() {
    super.initState();
    _syncMessageKeys();
  }

  @override
  void didUpdateWidget(covariant _MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final transcriptChanged =
        !_sameMessageIds(oldWidget.messages, widget.messages) ||
        oldWidget.streaming != widget.streaming;
    if (transcriptChanged) _captureAnchor();
    _syncMessageKeys();

    if (!oldWidget.isReconnecting && widget.isReconnecting) {
      _continuationTimer?.cancel();
      _awaitingReconnectHydration = true;
      _showContinuation = false;
    } else if (_awaitingReconnectHydration &&
        !widget.isReconnecting &&
        transcriptChanged) {
      _awaitingReconnectHydration = false;
      _showContinuation = true;
      _continuationTimer?.cancel();
      _continuationTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _showContinuation = false);
      });
    }

    if (transcriptChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreAnchor());
    }
  }

  void _syncMessageKeys() {
    for (final message in widget.messages) {
      _messageKeys.putIfAbsent(message.id, GlobalKey.new);
    }
  }

  bool _sameMessageIds(List<ChatMessage> before, List<ChatMessage> after) {
    if (before.length != after.length) return false;
    for (var i = 0; i < before.length; i++) {
      if (before[i].id != after[i].id) return false;
    }
    return true;
  }

  void _captureAnchor() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    _wasAtBottom = position.pixels <= position.minScrollExtent + 2;
    _pendingAnchor = null;
    if (_wasAtBottom) return;

    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox) return;
    _ViewportAnchor? firstVisible;
    for (final entry in _messageKeys.entries) {
      final render = entry.value.currentContext?.findRenderObject();
      if (render is! RenderBox || !render.attached) continue;
      final top = render.localToGlobal(Offset.zero, ancestor: viewport).dy;
      final bottom = top + render.size.height;
      if (bottom <= 0 || top >= viewport.size.height) continue;
      if (firstVisible == null || top < firstVisible.visualOffset) {
        firstVisible = _ViewportAnchor(messageId: entry.key, visualOffset: top);
      }
    }
    _pendingAnchor = firstVisible;
  }

  void _restoreAnchor() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    if (_wasAtBottom) {
      _controller.jumpTo(position.minScrollExtent);
    } else if (_pendingAnchor case _ViewportAnchor(
      :final messageId,
      :final visualOffset,
    )) {
      final viewport = _viewportKey.currentContext?.findRenderObject();
      final render = _messageKeys[messageId]?.currentContext
          ?.findRenderObject();
      if (viewport is RenderBox && render is RenderBox && render.attached) {
        final current = render
            .localToGlobal(Offset.zero, ancestor: viewport)
            .dy;
        final target = (position.pixels + current - visualOffset).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        _controller.jumpTo(target.toDouble());
      }
    }
    _pendingAnchor = null;
    final currentIds = {for (final message in widget.messages) message.id};
    _messageKeys.removeWhere((id, _) => !currentIds.contains(id));
  }

  @override
  void dispose() {
    _continuationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.messages;
    final streaming = widget.streaming;
    final itemCount = messages.length + (streaming != null ? 1 : 0);
    final colors = context.colors;

    return Stack(
      children: [
        ListView.separated(
          key: _viewportKey,
          controller: _controller,
          reverse: true,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          itemCount: itemCount,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (_, i) {
            if (streaming != null && i == 0) {
              return SizedBox(
                key: const ValueKey('streaming'),
                child: StreamingBubble(streaming),
              );
            }
            final msgIdx =
                messages.length - 1 - (i - (streaming != null ? 1 : 0));
            final msg = messages[msgIdx];
            return SizedBox(
              key: _messageKeys[msg.id],
              child: switch (msg) {
                UserMsg() => UserBubble(msg),
                AssistantMsg() => AssistantBubble(msg),
                ToolEvent() => ToolRequestCard(
                  tool: msg,
                  onDecide: widget.onDecide,
                ),
                CompactionMsg() => CompactionBubble(msg),
              },
            );
          },
        ),
        if (_showContinuation)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.bg,
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: Text(
                      'Reconnected · transcript updated',
                      style: TextStyle(
                        fontFamily: kMonoFamily,
                        fontSize: 12,
                        color: colors.muted2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

final class _ViewportAnchor {
  const _ViewportAnchor({required this.messageId, required this.visualOffset});

  final String messageId;
  final double visualOffset;
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: colors.muted, size: 48),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: colors.muted, fontSize: 14)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.onAccent,
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _PersistenceWarningBanner extends StatelessWidget {
  const _PersistenceWarningBanner({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      color: colors.warning.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(LucideIcons.databaseBackup, color: colors.warning, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: colors.text),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry sync')),
        ],
      ),
    );
  }
}

class _RevokedBanner extends StatelessWidget {
  final VoidCallback onRePair;
  const _RevokedBanner({required this.onRePair});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.red.shade900.withValues(alpha: 0.85),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(LucideIcons.unlink, color: Colors.white, size: 15),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Pairing revoked by Mac — re-pair to continue',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          GestureDetector(
            onTap: onRePair,
            child: const Text(
              'Re-pair',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One labelled key/value row in the session-info dialog. The value is
/// selectable so the user can copy the path / device name.
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: kMonoFamily,
              fontSize: 12,
              color: colors.muted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: TextStyle(
              fontFamily: kMonoFamily,
              fontSize: 13,
              color: colors.text,
            ),
          ),
        ],
      ),
    );
  }
}
