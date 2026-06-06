import 'package:cockpit/domain/entities/file_view.dart';
import 'package:cockpit/ui/cockpit/session/pane_item.dart';

/// Uma aba de viewer read-only de arquivo (texto/markdown/imagem). O conteúdo
/// ([view]) já vem classificado/lido pela VM (binário/vídeo nem chega aqui).
class FileViewerSession extends PaneItem {
  FileViewerSession({
    required this.id,
    required this.projectId,
    required this.path,
    required this.view,
  }) : title = path.split('/').where((p) => p.isNotEmpty).last,
       workingDirectory = path.contains('/')
           ? path.substring(0, path.lastIndexOf('/'))
           : path;

  @override
  final String id;
  @override
  final String projectId;
  @override
  final String title;
  @override
  final String workingDirectory;

  final String path;
  final FileView view;
}
