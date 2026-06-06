import 'package:cockpit/domain/entities/file_view.dart';

/// Lê e classifica um arquivo para o viewer (markdown / texto / imagem /
/// não-suportado). Contrato no domínio; impl (dart:io) em `data/filesystem/`.
abstract class FileReader {
  Future<FileView> read(String path);
}
