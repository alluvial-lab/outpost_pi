import 'dart:async';

import 'package:app/config/dependencies.dart';
import 'package:app/data/actions/actions_repository.dart' show ActionFailure;
import 'package:app/protocol/protocol.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/chat/quick_actions/states/quick_actions_state.dart';
import 'package:app/ui/chat/quick_actions/viewmodels/quick_actions_viewmodel.dart';
import 'package:app/ui/chat/quick_actions/widgets/dismiss_on_session_change.dart';
import 'package:app/ui/chat/quick_actions/widgets/model_picker_sheet.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

/// Plan/28 Wave C — entry point for the Quick Actions sheet from the
/// chat input bar. Provides a fresh [QuickActionsViewModel] scoped to
/// this sheet (and any sub-sheets it pushes) and wires the SnackBar
/// error stream from the chat scaffold's messenger so failures stay
/// visible after the sheet is dismissed.
///
/// Both the messenger and the `session_new` reset callback are captured
/// from the *page* context here, before the sheet pushes its own route —
/// the modal's builder context lives above the chat page's providers, so
/// `context.read<ChatViewModel>()` inside the sheet would not resolve.
Future<void> showQuickActionsSheet(BuildContext context) {
  final messenger = ScaffoldMessenger.of(context);
  final chat = context.read<ChatViewModel>();
  // Captured to auto-close the sheet if the tablet's selected session changes
  // out from under it (the sheet lives on the detail-pane navigator).
  final selection = context.read<SessionSelection>();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    isScrollControlled: true,
    showDragHandle: false,
    builder: (ctx) {
      return DismissOnSessionChange(
        selection: selection,
        child: ChangeNotifierProvider<QuickActionsViewModel>(
          create: (_) => injector.get<QuickActionsViewModel>(),
          child: QuickActionsSheetBody(
            messenger: messenger,
            onSessionReset: chat.clearActiveSession,
          ),
        ),
      );
    },
  );
}

/// Body of the Quick Actions sheet. Public so widget tests can drive the
/// real action handlers (close-on-success, toasts, session reset) with a
/// fake ViewModel instead of the replica harness they used before.
class QuickActionsSheetBody extends StatefulWidget {
  final ScaffoldMessengerState messenger;

  /// Invoked after the Pi acks a `session_new`, to wipe the local chat
  /// mirror. Optional so tests can omit it; in the app it is wired to
  /// [ChatViewModel.clearActiveSession].
  final Future<void> Function()? onSessionReset;

  const QuickActionsSheetBody({
    super.key,
    required this.messenger,
    this.onSessionReset,
  });

  @override
  State<QuickActionsSheetBody> createState() => _QuickActionsSheetBodyState();
}

class _QuickActionsSheetBodyState extends State<QuickActionsSheetBody> {
  StreamSubscription<String>? _errorSub;

  @override
  void initState() {
    super.initState();
    // Listener is attached in didChangeDependencies so we have a vm.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final vm = context.read<QuickActionsViewModel>();
      _errorSub = vm.errors.listen(_showError);
    });
  }

  void _showError(String message) => _showErrorOn(widget.messenger, message);

  void _showErrorOn(ScaffoldMessengerState messenger, String message) {
    if (!messenger.mounted) return;
    _toastOn(messenger, message, messenger.context.colors.error);
  }

  void _showInfoOn(ScaffoldMessengerState messenger, String message) {
    if (!messenger.mounted) return;
    _toastOn(messenger, message, messenger.context.colors.warning);
  }

  /// Toasts go through the chat scaffold's messenger (captured before the
  /// sheet opened) so success/failure feedback survives the sheet being
  /// popped on success.
  void _toastOn(ScaffoldMessengerState messenger, String message, Color color) {
    if (!messenger.mounted) return;
    final colors = messenger.context.colors;
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: colors.surface,
        behavior: SnackBarBehavior.floating,
        content: Text(
          message,
          style: TextStyle(fontFamily: kMonoFamily, fontSize: 12, color: color),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<QuickActionsViewModel>();
    final state = vm.state;
    final busyAction = state is QuickActionsBusy ? state.action : null;

    final colors = context.colors;
    final lowHeight = MediaQuery.sizeOf(context).height < 500;
    return AdaptiveSheetFrame(
      maxWidth: 640,
      maxHeight: 640,
      contentKey: const Key('quick-actions-sheet-scroll'),
      child: Material(
        key: const Key('quick-actions-adaptive-sheet'),
        color: colors.bg,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: lowHeight
              ? BorderRadius.circular(16)
              : const BorderRadius.vertical(top: Radius.circular(16)),
          side: BorderSide(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            _DragHandle(),
            const SizedBox(height: 6),
            const _SheetTitle(text: 'Quick actions'),
            const _Divider(),
            _ActionTile(
              key: const Key('qa-compact'),
              icon: LucideIcons.shrink,
              label: 'Compact context',
              subtitle: 'Summarize old turns to free room.',
              busy: busyAction == ActionName.sessionCompact,
              onTap: () => _onCompact(vm),
            ),
            const _Divider(),
            _ActionTile(
              key: const Key('qa-new-session'),
              icon: LucideIcons.sparkles,
              label: 'New session',
              subtitle: 'Clears the conversation on the Pi.',
              busy: busyAction == ActionName.sessionNew,
              onTap: () => _onNewSession(vm),
            ),
            _ActionTile(
              key: const Key('qa-restart-pi'),
              icon: Icons.restart_alt,
              label: 'Restart Pi process',
              subtitle: 'On a supervised Pi, restarts and reconnects.',
              busy: busyAction == ActionName.sessionNew,
              danger: true,
              onTap: () => _onRestartPi(vm),
            ),
            const _Divider(),
            _ActionTile(
              key: const Key('qa-send-debug-logs'),
              icon: LucideIcons.fileUp,
              label: _captureLabel(vm.captureDelivery),
              subtitle: _captureSubtitle(vm.captureDelivery),
              busy:
                  vm.captureDelivery is CaptureDeliveryReading ||
                  vm.captureDelivery is CaptureDeliverySending,
              onTap: () => vm.sendDebugLogs(),
            ),
            const _Divider(),
            _ModelRow(
              currentLabel: vm.currentModel?.name ?? vm.currentModelName,
              busy: busyAction == ActionName.modelSet,
              onTap: () => _openModelPicker(vm),
            ),
            const _Divider(),
            _ThinkingRow(
              current: vm.currentThinking,
              busy: busyAction == ActionName.thinkingSet,
              onPick: (level) => _onThinking(vm, level),
            ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }

  Future<void> _onCompact(QuickActionsViewModel vm) async {
    try {
      await vm.compact();
    } catch (_) {
      // Failure already surfaced as an error toast via `vm.errors`; leave
      // the sheet open so the user can retry.
      return;
    }
    // action_ok — just close the sheet (no success toast: compacting is a
    // quiet, frequent action and the toast was noise).
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _onNewSession(QuickActionsViewModel vm) async {
    // Capture only longer-lived owners before confirmation pops and disposes
    // the sheet/provider. The repository command deliberately outlives `vm`.
    final runNewSession = vm.detachedNewSessionCommand;
    final messenger = widget.messenger;
    final onSessionReset = widget.onSessionReset;
    final confirmed = await _confirmDestructiveAction(
      title: 'Start a new session?',
      content:
          'This clears the Pi-side conversation history. The current '
          'thread cannot be resumed.',
      confirmLabel: 'Start new',
    );
    if (!confirmed) return;
    try {
      await runNewSession();
    } on ActionFailure catch (e) {
      // The sheet is already closed, so its `vm.errors` listener is gone —
      // surface the failure toast directly through the captured messenger.
      _showErrorOn(messenger, e.message);
      return;
    } catch (_) {
      return;
    }
    // action_ok — wipe the local chat mirror so the UI reflects the fresh
    // session. The sheet is already closed; no success toast (quiet action,
    // the cleared chat is feedback enough).
    await onSessionReset?.call();
  }

  Future<void> _onRestartPi(QuickActionsViewModel vm) async {
    // Capture only longer-lived owners before confirmation pops and disposes
    // the sheet/provider. The repository command deliberately outlives `vm`.
    final runNewSession = vm.detachedNewSessionCommand;
    final messenger = widget.messenger;
    final onSessionReset = widget.onSessionReset;
    final confirmed = await _confirmDestructiveAction(
      title: 'Restart Pi process?',
      content:
          'This clears the current conversation. On a supervised Pi, '
          'the process will restart and this phone may disconnect briefly '
          'before it reconnects.',
      confirmLabel: 'Restart Pi',
      danger: true,
    );
    if (!confirmed) return;
    try {
      // Restart intentionally reuses `session_new`: the daemon ACKs this
      // request before exiting with 42, which makes the supervisor respawn a
      // fresh process. Interactive Pis perform only their normal new-session
      // behavior; the confirmation copy avoids promising a respawn there.
      await runNewSession();
    } on ActionFailure catch (e) {
      _showErrorOn(messenger, e.message);
      return;
    } catch (_) {
      return;
    }
    await onSessionReset?.call();
    _showInfoOn(
      messenger,
      'Session reset accepted; a supervised Pi may reconnect briefly.',
    );
  }

  /// Close the sheet before showing a destructive confirmation dialog.
  ///
  /// The root navigator is captured first because the sheet's context is
  /// disposed by the pop. Dialog buttons use their own context so this also
  /// works when the sheet is hosted by a nested detail-pane navigator.
  Future<bool> _confirmDestructiveAction({
    required String title,
    required String content,
    required String confirmLabel,
    bool danger = false,
  }) async {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).pop();
    final result = await showDialog<bool>(
      context: rootNavigator.context,
      builder: (dCtx) {
        final colors = dCtx.colors;
        return AlertDialog(
          backgroundColor: colors.bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: colors.border),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontFamily: kMonoFamily,
              fontSize: 14,
              color: colors.text,
            ),
          ),
          content: Text(
            content,
            style: TextStyle(
              fontFamily: kMonoFamily,
              fontSize: 12,
              color: colors.muted,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(fontFamily: kMonoFamily, color: colors.muted),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: danger ? colors.error : colors.accent,
                foregroundColor: colors.onAccent,
              ),
              onPressed: () => Navigator.of(dCtx).pop(true),
              child: Text(
                confirmLabel,
                style: const TextStyle(fontFamily: kMonoFamily),
              ),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  String _captureLabel(CaptureDeliveryState state) => switch (state) {
    CaptureDeliveryDelivered() => 'Debug logs delivered',
    CaptureDeliveryFailed() => 'Retry debug logs',
    _ => 'Send debug logs',
  };

  String _captureSubtitle(CaptureDeliveryState state) => switch (state) {
    CaptureDeliveryIdle() => 'Deliver the latest capture to this Pi session.',
    CaptureDeliveryReading() => 'Reading the latest capture…',
    CaptureDeliverySending(:final progress) =>
      'Sending… ${(progress * 100).round()}%',
    CaptureDeliveryDelivered(:final path) => 'Delivered to $path',
    CaptureDeliveryFailed(:final message) => '$message Tap to retry.',
  };

  Future<void> _onThinking(
    QuickActionsViewModel vm,
    ThinkingLevel level,
  ) async {
    try {
      await vm.setThinking(level);
    } catch (_) {
      /* surfaced via vm.errors */
    }
  }

  Future<void> _openModelPicker(QuickActionsViewModel vm) async {
    await showModelPickerSheet(context, vm: vm);
  }
}

// ---------------------------------------------------------------------------
// UI pieces
// ---------------------------------------------------------------------------

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: context.colors.border,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  final String text;
  const _SheetTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            fontFamily: kMonoFamily,
            fontSize: 12,
            color: context.colors.muted,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      Divider(color: context.colors.border, height: 1, thickness: 1);
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool busy;
  final bool danger;
  final VoidCallback onTap;
  const _ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.busy,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final actionColor = danger ? colors.error : colors.accent;
    return InkWell(
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: actionColor, size: 18),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: kMonoFamily,
                      fontSize: 13,
                      color: danger ? colors.error : colors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    key: const Key('quick-action-description'),
                    style: TextStyle(
                      fontFamily: kMonoFamily,
                      fontSize: 12,
                      color: colors.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (busy)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: actionColor,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  /// Display label — `WireModel.name` when the catalogue is loaded,
  /// otherwise the `room_meta.model` string. `null` falls back to the
  /// generic placeholder. Reads cheap so the picker can lazy-load.
  final String? currentLabel;
  final bool busy;
  final VoidCallback onTap;
  const _ModelRow({
    required this.currentLabel,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = currentLabel ?? (busy ? 'Switching…' : 'Choose a model');
    return InkWell(
      key: const Key('qa-model-row'),
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(LucideIcons.memoryStick, color: colors.accent, size: 18),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Model',
                    key: const Key('quick-action-model-label'),
                    style: TextStyle(
                      fontFamily: kMonoFamily,
                      fontSize: 12,
                      color: colors.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: kMonoFamily,
                      fontSize: 13,
                      color: colors.text,
                    ),
                  ),
                ],
              ),
            ),
            if (busy)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: colors.accent,
                ),
              )
            else
              Icon(LucideIcons.chevronRight, color: colors.muted, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ThinkingRow extends StatelessWidget {
  final ThinkingLevel? current;
  final bool busy;
  final ValueChanged<ThinkingLevel> onPick;
  const _ThinkingRow({
    required this.current,
    required this.busy,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.brain, color: colors.accent, size: 18),
              const SizedBox(width: 14),
              Text(
                'Thinking',
                style: TextStyle(
                  fontFamily: kMonoFamily,
                  fontSize: 11,
                  color: colors.muted,
                ),
              ),
              const Spacer(),
              if (busy)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: colors.accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _ThinkingSegmented(current: current, disabled: busy, onPick: onPick),
        ],
      ),
    );
  }
}

class _ThinkingSegmented extends StatelessWidget {
  final ThinkingLevel? current;
  final bool disabled;
  final ValueChanged<ThinkingLevel> onPick;
  const _ThinkingSegmented({
    required this.current,
    required this.disabled,
    required this.onPick,
  });

  // Short label shown in the segmented buttons. Matches the SDK's
  // ThinkingLevel order (off → xhigh).
  static const _labels = <ThinkingLevel, String>{
    ThinkingLevel.off: 'off',
    ThinkingLevel.minimal: 'min',
    ThinkingLevel.low: 'low',
    ThinkingLevel.medium: 'med',
    ThinkingLevel.high: 'high',
    ThinkingLevel.xhigh: 'x',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.colors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns =
              constraints.maxWidth < 48 * ThinkingLevel.values.length
              ? 3
              : ThinkingLevel.values.length;
          final itemWidth = constraints.maxWidth / columns;
          return Wrap(
            children: [
              for (final level in ThinkingLevel.values)
                SizedBox(
                  width: itemWidth,
                  child: _SegButton(
                    key: Key('qa-thinking-${level.wire}'),
                    label: _labels[level]!,
                    selected: current == level,
                    disabled: disabled,
                    onTap: () => onPick(level),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SegButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;
  const _SegButton({
    super.key,
    required this.label,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: '$label thinking level',
      button: true,
      selected: selected,
      enabled: !disabled,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: disabled ? null : onTap,
        child: SizedBox(
          height: 48,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: double.infinity,
              height: 32,
              decoration: BoxDecoration(
                color: selected
                    ? colors.accent.withValues(alpha: 0.15)
                    : Colors.transparent,
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: kMonoFamily,
                    fontSize: 11,
                    color: disabled
                        ? colors.muted.withValues(alpha: 0.5)
                        : selected
                        ? colors.accent
                        : colors.text,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
