import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/file_reader.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';

/// Classify files by extension and content.
///
/// Video, audio, and image results carry only the path. Markdown and readable
/// UTF-8 text without null bytes are loaded up to 2 MB; binary, oversized, or
/// non-UTF-8 files are reported as [FileViewUnsupported].
class FileReaderImpl implements FileReader {
  const FileReaderImpl();

  static const int _maxTextBytes = 2 * 1024 * 1024;
  static const Set<String> _markdown = {'md', 'mdx', 'markdown'};
  static const Set<String> _image = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
    'ico',
  };
  static const Set<String> _video = {
    'mp4',
    'mov',
    'avi',
    'mkv',
    'webm',
    'm4v',
    'wmv',
    'flv',
  };
  static const Set<String> _audio = {
    'mp3',
    'wav',
    'aac',
    'm4a',
    'flac',
    'ogg',
    'opus',
  };

  @override
  Future<FileView> read(String path) async {
    final ext = _ext(path);
    // A/V and image results carry only the path; the player or widget loads the
    // content without a size limit. Decide before reading anything from disk.
    if (_video.contains(ext)) return FileViewVideo(path);
    if (_audio.contains(ext)) return FileViewAudio(path);
    if (_image.contains(ext)) return FileViewImage(path);

    final file = File(path);
    if (!await file.exists()) return const FileViewUnsupported();
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file || stat.size > _maxTextBytes) {
      return const FileViewUnsupported();
    }

    final bytes = await file.readAsBytes();
    if (_looksBinary(bytes)) return const FileViewUnsupported();
    final String text;
    try {
      text = utf8.decode(bytes);
    } catch (_) {
      return const FileViewUnsupported();
    }

    if (_markdown.contains(ext)) return FileViewMarkdown(text);
    // SVG is renderable XML, so expose both editable source and a preview.
    if (ext == 'svg') return FileViewSvg(path, text);
    return FileViewText(text, language: ext.isEmpty ? null : ext);
  }

  @override
  Future<bool> write(String path, String content) async {
    try {
      await File(path).writeAsString(content);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  @override
  Stream<void> watch(String path) =>
      // macOS uses FSEvents. Preserve stream errors so the consuming owner can
      // surface a failed watcher instead of silently disabling live reload.
      File(path)
          .watch(events: FileSystemEvent.modify | FileSystemEvent.delete)
          .map((_) {});

  /// Detect likely binary content by a null byte in the first ~8 KB.
  bool _looksBinary(List<int> bytes) {
    final n = bytes.length < 8000 ? bytes.length : 8000;
    for (var i = 0; i < n; i++) {
      if (bytes[i] == 0) return true;
    }
    return false;
  }

  String _ext(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }
}
