import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter/widgets.dart';

/// Provide Material-free hover and tap behavior for custom clickable surfaces.
///
/// Replaces `InkWell` for list rows, menu items, and chips, with a subtle hover
/// background defaulting to `context.colors.panel3`. Use shadcn buttons for
/// primary, secondary, or destructive actions; this widget covers generic
/// clickable areas with hover emphasis, like shadcn's internal `Clickable`.
class HoverTap extends StatefulWidget {
  const HoverTap({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.borderRadius = const BorderRadius.all(Radius.circular(7)),
    this.color,
    this.hoverColor,
    this.border,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;

  /// Base background when not hovered; `null` is transparent.
  final Color? color;

  /// Hover background; `null` falls back to `context.colors.panel3`.
  final Color? hoverColor;

  /// Optional border that remains constant at rest and on hover.
  final BoxBorder? border;
  final MouseCursor cursor;

  @override
  State<HoverTap> createState() => _HoverTapState();
}

class _HoverTapState extends State<HoverTap> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final hoverColor = widget.hoverColor ?? context.colors.panel3;
    final bg = _hover && enabled ? hoverColor : widget.color;
    final inner = widget.padding == null
        ? widget.child
        : Padding(padding: widget.padding!, child: widget.child);
    return MouseRegion(
      cursor: enabled ? widget.cursor : MouseCursor.defer,
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: enabled ? (_) => setState(() => _hover = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: widget.borderRadius,
            border: widget.border,
          ),
          child: inner,
        ),
      ),
    );
  }
}
