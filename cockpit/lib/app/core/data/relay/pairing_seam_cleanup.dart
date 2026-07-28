import 'dart:io';

/// Remove abandoned Cockpit pairing-code seams left by a crashed process.
///
/// The scan is deliberately limited to Cockpit's exact `createTemp` prefix and
/// directories that do not grant group or world permissions. It never walks or
/// deletes arbitrary entries in the system temporary directory.
class PairingSeamCleanup {
  PairingSeamCleanup._();

  static const String _prefix = 'outpost-pi-pair-';

  /// Recover abandoned bearer-token seams before the app creates a new one.
  static Future<int> sweep({Directory? tempDirectory}) async {
    final root = tempDirectory ?? Directory.systemTemp;
    var removed = 0;
    try {
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! Directory || !_isCandidate(entity)) continue;
        // Candidate validation happens before recursive deletion.
        try {
          final stat = await entity.stat();
          if (stat.type != FileSystemEntityType.directory ||
              !_isOwnerOnly(stat.mode)) {
            continue;
          }
          await entity.delete(recursive: true);
          removed++;
        } on FileSystemException {
          // Another Cockpit instance or cleanup operation may own the seam.
        }
      }
    } on FileSystemException {
      // A missing or inaccessible temp root must not prevent Cockpit startup.
    }
    return removed;
  }

  static bool _isCandidate(Directory entity) {
    final segments = entity.path
        .split(Platform.pathSeparator)
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final name = segments.isEmpty ? '' : segments.last;
    return name.startsWith(_prefix) &&
        RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name.substring(_prefix.length));
  }

  static bool _isOwnerOnly(int mode) => mode & 0x3f == 0;
}
