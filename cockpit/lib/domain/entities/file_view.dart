/// O conteúdo de um arquivo aberto no viewer, já classificado.
sealed class FileView {
  const FileView();
}

/// Markdown (.md/.mdx) — renderizado com gpt_markdown.
final class FileViewMarkdown extends FileView {
  const FileViewMarkdown(this.text);
  final String text;
}

/// Texto legível (.js/.json/…) — texto puro por enquanto (highlight depois).
final class FileViewText extends FileView {
  const FileViewText(this.text, {this.language});
  final String text;

  /// Dica de linguagem (extensão), para highlight futuro.
  final String? language;
}

/// Imagem (PNG/JPEG/SVG/…) — só o caminho; o widget carrega.
final class FileViewImage extends FileView {
  const FileViewImage(this.path);
  final String path;
}

/// Binário/vídeo/grande demais — **não abre**.
final class FileViewUnsupported extends FileView {
  const FileViewUnsupported();
}
