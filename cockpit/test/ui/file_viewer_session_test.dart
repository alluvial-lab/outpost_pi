import 'dart:io';

import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/widgets/file_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reload failure diagnostic retains class but not file path or stack',
    () {
      const path = '/Users/operator/workspace/secret.dart';
      final error = FileSystemException('read failed', path);

      final diagnostic = fileViewerReloadFailureDiagnostic(error);

      expect(diagnostic, contains('FileSystemException'));
      expect(diagnostic, isNot(contains(path)));
      expect(diagnostic, isNot(contains('read failed')));
      expect(diagnostic, isNot(contains('StackTrace')));
    },
  );

  group('FileViewerSession auto-pinning', () {
    test('setting dirty to true on a preview session turns off isPreview', () {
      final session = FileViewerSession(
        id: 's1',
        projectId: 'p1',
        path: '/workspace/file.txt',
        view: const FileViewUnsupported(),
        isPreview: true,
      );

      expect(session.isPreview, isTrue);
      expect(session.dirty, isFalse);

      // Mark the session dirty (simulate user typing/editing)
      session.setDirty(true);

      // Verify it is now dirty and no longer a preview tab
      expect(session.dirty, isTrue);
      expect(session.isPreview, isFalse);
    });

    test('setting dirty to false does not restore isPreview', () {
      final session = FileViewerSession(
        id: 's1',
        projectId: 'p1',
        path: '/workspace/file.txt',
        view: const FileViewUnsupported(),
        isPreview: true,
      );

      session.setDirty(true);
      expect(session.isPreview, isFalse);

      // Revert dirty status (simulate undo/save)
      session.setDirty(false);

      expect(session.dirty, isFalse);
      // Should remain pinned (isPreview remains false)
      expect(session.isPreview, isFalse);
    });
  });
}
