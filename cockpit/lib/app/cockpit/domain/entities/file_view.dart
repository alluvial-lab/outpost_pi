/// Represent classified content for a file opened in the viewer.
sealed class FileView {
  const FileView();
}

/// Render Markdown files (`.md` and `.mdx`) with `gpt_markdown`.
final class FileViewMarkdown extends FileView {
  const FileViewMarkdown(this.text);
  final String text;
}

/// Render readable text files as plain text until syntax highlighting is added.
final class FileViewText extends FileView {
  const FileViewText(this.text, {this.language});
  final String text;

  /// Optional extension-based language hint for future syntax highlighting.
  final String? language;
}

/// Identify a raster image by path so the widget can load it.
final class FileViewImage extends FileView {
  const FileViewImage(this.path);
  final String path;
}

/// Provide an SVG as both editable XML source and a previewable image.
///
/// Carries [text] for source editing and [path] as the preview origin.
final class FileViewSvg extends FileView {
  const FileViewSvg(this.path, this.text);
  final String path;
  final String text;
}

/// Identify an audio file by path for the `media_kit` player (Plan 46).
final class FileViewAudio extends FileView {
  const FileViewAudio(this.path);
  final String path;
}

/// Identify a video file by path for the `media_kit` player (Plan 46).
final class FileViewVideo extends FileView {
  const FileViewVideo(this.path);
  final String path;
}

/// Mark a binary or oversized file that the viewer must not open.
final class FileViewUnsupported extends FileView {
  const FileViewUnsupported();
}
