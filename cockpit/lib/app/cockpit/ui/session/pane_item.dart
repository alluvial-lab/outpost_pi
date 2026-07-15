import 'package:flutter/foundation.dart';

/// Define the shared lifecycle for a live multiplexer tab.
///
/// The ViewModel stores agent, terminal, and file-viewer tabs as [PaneItem]
/// instances; the UI chooses a renderer from the concrete subtype.
abstract class PaneItem extends ChangeNotifier {
  String get id;
  String get projectId;
  String get title;
  String get workingDirectory;

  /// Report a completed agent turn that the user has not yet viewed.
  ///
  /// Non-agent tabs retain the default `false` value.
  bool get unseenFinish => false;
  void clearUnseen() {}

  /// Public change hook for the workspace projection, which owns live tab
  /// resources but is not itself a [ChangeNotifier] subclass.
  void notifyItemChanged() => notifyListeners();
}
