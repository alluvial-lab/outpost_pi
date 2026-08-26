import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolve current JSON and legacy Hive locations for Cockpit state.
final class CockpitStoragePaths {
  const CockpitStoragePaths._();

  /// Keep development state separate from an installed production Cockpit.
  static const String storageSubdirectory = kDebugMode
      ? 'cockpit-debug'
      : 'cockpit';

  /// Resolve and create the directory containing versioned JSON stores.
  ///
  /// Windows uses Application Support rather than Documents to avoid Known
  /// Folder Move and OneDrive. macOS and Linux retain the existing Documents
  /// root.
  static Future<String> stateDirectory() async {
    final root = Platform.isWindows
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(dataDirectoryUnder(root.path), 'state'));
    await directory.create(recursive: true);
    return directory.path;
  }

  /// Return legacy Hive directories in deterministic newest-install order.
  ///
  /// The current Documents location comes first, followed by Application
  /// Support for installations that may already have moved state. Duplicates
  /// are removed after native normalization.
  static Future<List<String>> legacyHiveDirectories() async {
    final documents = await getApplicationDocumentsDirectory();
    final applicationSupport = await getApplicationSupportDirectory();
    return legacyDirectoriesFromRoots(
      documentsRoot: documents.path,
      applicationSupportRoot: applicationSupport.path,
    );
  }

  /// Build Cockpit's debug/production data directory under [root].
  static String dataDirectoryUnder(String root, [p.Context? context]) {
    final paths = context ?? p.context;
    return paths.normalize(paths.join(root.trim(), storageSubdirectory));
  }

  /// Select the platform default and append the canonical state directory.
  ///
  /// Explicit roots and path context keep Windows placement testable on any
  /// host without representing that test as a real Windows smoke.
  static String defaultStateDirectory({
    required bool isWindows,
    required String applicationSupportRoot,
    required String documentsRoot,
    p.Context? context,
  }) {
    final paths = context ?? p.context;
    final root = isWindows ? applicationSupportRoot : documentsRoot;
    return paths.normalize(
      paths.join(dataDirectoryUnder(root, paths), 'state'),
    );
  }

  /// Build and de-duplicate the deterministic legacy search list.
  static List<String> legacyDirectoriesFromRoots({
    required String documentsRoot,
    required String applicationSupportRoot,
    p.Context? context,
  }) {
    final paths = context ?? p.context;
    final candidates = <String>[
      dataDirectoryUnder(documentsRoot, paths),
      dataDirectoryUnder(applicationSupportRoot, paths),
    ];
    return <String>{
      for (final String candidate in candidates) paths.normalize(candidate),
    }.toList(growable: false);
  }
}
