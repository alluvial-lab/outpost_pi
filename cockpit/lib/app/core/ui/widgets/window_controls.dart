import 'dart:io';

import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:window_manager/window_manager.dart';

Future<void> _toggleMaximize() async {
  if (await windowManager.isMaximized()) {
    await windowManager.unmaximize();
  } else {
    await windowManager.maximize();
  }
}

/// Render a draggable custom title bar that maximizes on double-click.
///
/// Keeps [DragToMoveArea] in a background layer behind [children] rather than
/// wrapping them. Its `DoubleTapGestureRecognizer` holds the gesture arena for
/// `kDoubleTapTimeout` while awaiting a second click; descendant buttons would
/// inherit that delay. With dragging behind the controls, buttons receive taps
/// immediately while gaps, `Spacer`, and [Row] text pass pointers through to the
/// draggable layer. Empty title-bar areas therefore still drag and maximize.
class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({super.key, required this.children});

  /// Title-bar controls and content placed directly in a [Row].
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Stack(
        children: [
          // Keep the draggable background behind the buttons; see class docs.
          const Positioned.fill(
            child: DragToMoveArea(child: SizedBox.expand()),
          ),
          // The interactive layer receives taps without the gesture-arena hold.
          Positioned.fill(
            child: Padding(
              // On Windows/Linux, place caption controls flush right.
              padding: EdgeInsets.only(
                left: 18,
                right: Platform.isWindows || Platform.isLinux ? 0 : 12,
              ),
              child: Row(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

/// Render macOS-style close, minimize, and maximize controls on the left.
///
/// Renders nothing on non-macOS platforms; Windows controls appear on the right
/// through [WindowControlsTrailing].
class WindowControls extends StatefulWidget {
  const WindowControls({super.key});

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) return const SizedBox.shrink();
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(
        children: [
          _light(const Color(0xFFFF5F57), Icons.close, windowManager.close),
          const SizedBox(width: 8),
          _light(const Color(0xFFFEBC2E), Icons.remove, windowManager.minimize),
          const SizedBox(width: 8),
          _light(const Color(0xFF28C840), Icons.add, _toggleMaximize),
        ],
      ),
    );
  }

  Widget _light(Color color, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 12,
          height: 12,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: _hover
              ? Icon(icon, size: 8, color: Colors.black.withValues(alpha: 0.55))
              : null,
        ),
      ),
    );
  }
}

/// Render Windows/Linux-style window controls at the right edge of the top bar.
///
/// Uses square minimize, maximize, and close buttons with hover backgrounds; the
/// close button turns red. Renders nothing on macOS, where [WindowControls]
/// provides left-side traffic-light controls.
class WindowControlsTrailing extends StatelessWidget {
  const WindowControlsTrailing({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows && !Platform.isLinux) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WinButton(
          icon: Icons.remove,
          tooltip: 'Minimize',
          onTap: windowManager.minimize,
        ),
        _WinButton(
          icon: Icons.crop_square,
          tooltip: 'Maximize',
          onTap: _toggleMaximize,
        ),
        _WinButton(
          icon: Icons.close,
          tooltip: 'Close',
          onTap: windowManager.close,
          danger: true,
        ),
      ],
    );
  }
}

class _WinButton extends StatefulWidget {
  const _WinButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final Color? bg = _hover
        ? (widget.danger ? const Color(0xFFE81123) : colors.panel3)
        : null;
    final Color fg = _hover && widget.danger ? Colors.white : colors.text2;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        tooltip: (context) => TooltipContainer(child: Text(widget.tooltip)),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 46,
            height: 46,
            color: bg ?? Colors.transparent,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 16, color: fg),
          ),
        ),
      ),
    );
  }
}
