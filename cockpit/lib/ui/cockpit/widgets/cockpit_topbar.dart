import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Top bar (~46px) customizada — substitui a barra nativa da janela. Semáforo
/// macOS **funcional** (fecha/minimiza/maximiza) · toggle da rail · nome do
/// projeto · botão "Abrir". A barra inteira arrasta a janela ([DragToMoveArea]).
class CockpitTopbar extends StatelessWidget {
  const CockpitTopbar({
    super.key,
    required this.projectName,
    required this.railVisible,
    required this.treeVisible,
    required this.onToggleRail,
    required this.onToggleTree,
    required this.onOpen,
  });

  final String projectName;
  final bool railVisible;
  final bool treeVisible;
  final VoidCallback onToggleRail;
  final VoidCallback onToggleTree;
  final Future<bool> Function() onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DragToMoveArea(
      child: Container(
        height: 46,
        padding: const EdgeInsets.only(left: 18, right: 12),
        decoration: BoxDecoration(
          color: colors.bg,
          border: Border(bottom: BorderSide(color: colors.border)),
        ),
        child: Row(
          children: [
            const _TrafficLights(),
            const SizedBox(width: 12),
            _IconBtn(
              icon: Icons.view_sidebar_outlined,
              tooltip: 'Recolher sidebar',
              active: !railVisible,
              onTap: onToggleRail,
            ),
            const SizedBox(width: 8),
            Text(
              projectName,
              style: context.typo.title.copyWith(
                fontSize: 14,
                color: colors.text,
              ),
            ),
            const Spacer(),
            _OpenButton(onTap: onOpen),
            const SizedBox(width: 8),
            _IconBtn(
              icon: Icons.view_sidebar_outlined,
              tooltip: 'Mostrar/ocultar arquivos',
              active: treeVisible,
              onTap: onToggleTree,
            ),
          ],
        ),
      ),
    );
  }
}

/// Semáforo macOS funcional — os símbolos aparecem ao passar o mouse no cluster.
class _TrafficLights extends StatefulWidget {
  const _TrafficLights();

  @override
  State<_TrafficLights> createState() => _TrafficLightsState();
}

class _TrafficLightsState extends State<_TrafficLights> {
  bool _hover = false;

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(
        children: [
          _light(const Color(0xFFFF5F57), Icons.close, windowManager.close),
          const SizedBox(width: 8),
          _light(
            const Color(0xFFFEBC2E),
            Icons.remove,
            windowManager.minimize,
          ),
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

class _OpenButton extends StatelessWidget {
  const _OpenButton({required this.onTap});
  final Future<bool> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.accent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => onTap(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_open, size: 14, color: Colors.white),
              const SizedBox(width: 7),
              Text(
                'Abrir',
                style: context.typo.label.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? colors.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: onTap,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(
              icon,
              size: 17,
              color: active ? colors.accentText : colors.text3,
            ),
          ),
        ),
      ),
    );
  }
}
