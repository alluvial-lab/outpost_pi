import 'package:flutter/foundation.dart';

/// Bridge the global Cmd+L/Ctrl+L shortcut to the active agent composer.
///
/// The handler in `main.dart` remains in the focus chain even when no control
/// is focused. `CockpitPage` registers its focus action here and clears it to
/// `null` while the shell is unmounted.
VoidCallback? requestFocusActiveComposer;
