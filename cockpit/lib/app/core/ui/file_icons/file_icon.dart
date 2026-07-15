import 'package:cockpit/app/core/ui/file_icons/file_icon_map.g.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Resolve a file's material-icon-theme icon name from its full name.
///
/// Mirrors VS Code precedence: exact name → longest compound extension → final
/// extension → default icon. For example, `app.module.ts` matches `module.ts`
/// (Angular) before `ts`, `.gitignore` matches by exact name, and `photo.PNG`
/// matches case-insensitively.
String fileIconName(String fileName) {
  final lower = fileName.toLowerCase();
  final byName = kFileNameIcons[lower];
  if (byName != null) return byName;

  final parts = lower.split('.');
  for (var k = 1; k < parts.length; k++) {
    final ext = parts.sublist(k).join('.');
    final byExt = kFileExtensionIcons[ext];
    if (byExt != null) return byExt;
  }
  return kDefaultFileIcon;
}

/// Resolve a folder icon from its normalized name and open/closed state.
String folderIconName(String folderName, {bool open = false}) {
  final key = _normalizeFolder(folderName);
  final map = open ? kFolderOpenIcons : kFolderIcons;
  return map[key] ?? (open ? kDefaultFolderOpenIcon : kDefaultFolderIcon);
}

/// Normalize a folder name like the map generator.
///
/// Lowercases the name, removes the `__x__` envelope, and strips leading
/// `.`/`_`/`-` variants that material-icon-theme maps to the same icon.
String _normalizeFolder(String name) {
  var s = name.toLowerCase();
  if (s.length > 4 && s.startsWith('__') && s.endsWith('__')) {
    s = s.substring(2, s.length - 2);
  }
  var i = 0;
  while (i < s.length && (s[i] == '.' || s[i] == '_' || s[i] == '-')) {
    i++;
  }
  return s.substring(i);
}

const String _kAssetDir = 'assets/file_icons';

/// Render a file or folder's color material-icon-theme SVG.
///
/// Preserves the theme's original colors without tinting; row selection is
/// indicated by the background and text color rather than the icon.
class FileTypeIcon extends StatelessWidget {
  const FileTypeIcon.file(this.name, {super.key, this.size = 16})
    : _isFolder = false,
      _open = false;

  const FileTypeIcon.folder(
    this.name, {
    super.key,
    bool open = false,
    this.size = 16,
  }) : _isFolder = true,
       _open = open;

  /// File or folder basename, not its path.
  final String name;
  final double size;
  final bool _isFolder;
  final bool _open;

  @override
  Widget build(BuildContext context) {
    final icon = _isFolder
        ? folderIconName(name, open: _open)
        : fileIconName(name);
    return SvgPicture.asset(
      '$_kAssetDir/$icon.svg',
      width: size,
      height: size,
      // Reserve space while the asset decodes to prevent row layout shifts.
      placeholderBuilder: (_) => SizedBox(width: size, height: size),
    );
  }
}
