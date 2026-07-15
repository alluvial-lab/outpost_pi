import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Describe an item rendered by [showAppMenu].
///
/// Places an optional icon and label on the left, a check on the right when
/// [selected], and uses the error color when [danger] marks a destructive action.
class AppMenuItem<T> {
  const AppMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.selected = false,
    this.danger = false,
  });

  final T value;
  final String label;
  final IconData? icon;
  final bool selected;
  final bool danger;
}

/// Track the currently open menu popover.
///
/// shadcn `showPopover` does not close itself when another opens: a secondary
/// tap on a second item fires before the barrier dismisses the first. Tracking
/// the active menu lets callers close it before opening another.
OverlayCompleter<dynamic>? _activeMenu;

/// Register [overlay] as active, closing the previous menu if still open.
///
/// Shared by [showAppMenu] and other app menu popovers to keep at most one menu
/// open.
void trackMenuOverlay(OverlayCompleter<dynamic> overlay) {
  if (_activeMenu?.isCompleted == false) _activeMenu!.remove();
  _activeMenu = overlay;
}

/// Show the app's compact shadcn popup menu.
///
/// By default, anchors below the calling widget through [context]. Supplying
/// [globalPosition] anchors at the click point for a context menu. shadcn flips
/// the popover when space is constrained. Returns the selected value, or `null`
/// when dismissed. All app menus use this shared component.
Future<T?> showAppMenu<T>(
  BuildContext context, {
  required List<AppMenuItem<T>> items,
  double minWidth = 200,
  Offset? globalPosition,
}) {
  final colors = context.colors;
  final anchored = globalPosition == null;

  final overlay = showPopover<T>(
    context: context,
    // Anchor at the context-menu click point or the dropdown trigger.
    position: globalPosition,
    alignment: Alignment.topLeft,
    anchorAlignment: anchored ? Alignment.bottomLeft : Alignment.topLeft,
    offset: anchored ? const Offset(0, 4) : null,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth, maxWidth: 320),
      // DropdownMenu wraps MenuButtons in the required MenuGroup + MenuPopup.
      child: DropdownMenu(
        children: [
          for (final item in items)
            MenuButton(
              leading: item.icon != null
                  ? Icon(
                      item.icon,
                      size: 15,
                      color: item.danger ? colors.error : colors.text3,
                    )
                  : null,
              trailing: item.selected
                  ? Icon(Icons.check, size: 14, color: colors.accentText)
                  : null,
              onPressed: (ctx) {
                closeOverlay<T>(ctx, item.value);
              },
              child: Text(
                item.label,
                overflow: TextOverflow.ellipsis,
                style: context.typo.body.copyWith(
                  fontSize: 13,
                  color: item.danger ? colors.error : colors.text,
                ),
              ),
            ),
        ],
      ),
    ),
  );
  trackMenuOverlay(overlay);
  return overlay.future;
}
