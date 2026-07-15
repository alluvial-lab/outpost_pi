import 'package:flutter/widgets.dart';

import 'app_colors.dart';
import 'app_typography.dart';
import 'syntax_colors.dart';

/// Install Cockpit's bespoke color, typography, and syntax tokens in the tree.
///
/// These tokens previously used Material `ThemeExtension`s accessed through
/// `Theme.of(context).extension<…>()`. Because the root is now `ShadcnApp` and
/// shadcn `ThemeData` has no `.extension<>()`, this dedicated `InheritedWidget`
/// anchors them while preserving the `context.colors`, `context.typo`, and
/// `context.syntax` accessors in `theme_extensions.dart`.
@immutable
class CockpitTheme extends InheritedWidget {
  const CockpitTheme({
    super.key,
    required this.colors,
    required this.typo,
    required this.syntax,
    required super.child,
  });

  final AppColors colors;
  final AppTypography typo;
  final SyntaxColors syntax;

  static CockpitTheme? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CockpitTheme>();

  static CockpitTheme of(BuildContext context) {
    final theme = maybeOf(context);
    assert(theme != null, 'CockpitTheme not found in the widget tree.');
    return theme!;
  }

  @override
  bool updateShouldNotify(CockpitTheme oldWidget) =>
      colors != oldWidget.colors ||
      typo != oldWidget.typo ||
      syntax != oldWidget.syntax;
}
