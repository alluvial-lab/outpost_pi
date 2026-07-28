/// Validate a user-supplied file or directory name as a child of a parent path.
class FileNameValidator {
  /// Validate [name] and return the normalized child path when accepted.
  static FileNameCheck validate(String parentPath, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const FileNameCheck.invalid('Name cannot be empty.');
    }
    if (trimmed.contains('/') || trimmed.contains(r'\')) {
      return const FileNameCheck.invalid(
        'Name cannot contain path separators.',
      );
    }
    if (trimmed.contains(':')) {
      return const FileNameCheck.invalid(
        'Name cannot contain drive specifiers.',
      );
    }
    for (final unit in trimmed.codeUnits) {
      if (unit < 0x20 || unit == 0x7f) {
        return const FileNameCheck.invalid(
          'Name cannot contain control characters.',
        );
      }
    }
    if (trimmed == '.' || trimmed == '..') {
      return const FileNameCheck.invalid('Invalid name.');
    }

    final parent = _normalize(parentPath);
    final child = _normalize('$parent/$trimmed');
    final boundary = parent == '/' || parent.endsWith('/')
        ? parent
        : '$parent/';
    if (child == parent || !child.startsWith(boundary)) {
      return const FileNameCheck.invalid('Name must remain inside its parent.');
    }
    return FileNameCheck.valid(child);
  }

  static String _normalize(String path) {
    final unified = path.replaceAll(r'\', '/');
    final absolute = unified.startsWith('/');
    final drive = RegExp(r'^[A-Za-z]:').hasMatch(unified)
        ? unified.substring(0, 2)
        : '';
    final body = drive.isNotEmpty ? unified.substring(2) : unified;
    final parts = body.split('/');
    final kept = <String>[];
    for (final part in parts) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (kept.isNotEmpty && kept.last != '..') {
          kept.removeLast();
        } else if (!absolute && drive.isEmpty) {
          kept.add(part);
        }
      } else {
        kept.add(part);
      }
    }
    final prefix = drive.isNotEmpty ? '$drive/' : (absolute ? '/' : '');
    final result = '$prefix${kept.join('/')}';
    if (result.isEmpty) return '.';
    final isDriveRoot = RegExp(r'^[A-Za-z]:/$').hasMatch(result);
    return result.length > 1 && result.endsWith('/') && !isDriveRoot
        ? result.substring(0, result.length - 1)
        : result;
  }
}

/// Result of validating a file or directory child name.
class FileNameCheck {
  const FileNameCheck.valid(this.path) : error = null;
  const FileNameCheck.invalid(this.error) : path = null;

  /// Normalized path, or `null` when rejected.
  final String? path;

  /// User-facing validation error, or `null` when accepted.
  final String? error;

  /// Whether the name passed validation.
  bool get isValid => error == null;
}
