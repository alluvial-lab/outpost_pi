/// Represent an item in the file tree, either a directory or a file.
class FileNode {
  const FileNode({
    required this.name,
    required this.path,
    required this.isDirectory,
  });

  final String name;
  final String path;
  final bool isDirectory;
}
