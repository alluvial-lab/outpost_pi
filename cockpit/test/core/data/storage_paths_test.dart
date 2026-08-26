import 'package:cockpit/app/core/data/storage/storage_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'Windows state defaults to Application Support with native separators',
    () {
      final windows = p.Context(style: p.Style.windows);

      final path = CockpitStoragePaths.defaultStateDirectory(
        isWindows: true,
        applicationSupportRoot: r'C:\Users\operator\AppData\Roaming',
        documentsRoot: r'C:\Users\operator\OneDrive\Documents',
        context: windows,
      );

      expect(
        path,
        windows.join(
          r'C:\Users\operator\AppData\Roaming',
          CockpitStoragePaths.storageSubdirectory,
          'state',
        ),
      );
      expect(path, isNot(contains('/')));
      expect(path, isNot(contains('OneDrive')));
    },
  );

  test('non-Windows state retains the Documents root', () {
    final posix = p.Context(style: p.Style.posix);

    final path = CockpitStoragePaths.defaultStateDirectory(
      isWindows: false,
      applicationSupportRoot: '/home/operator/.local/share',
      documentsRoot: '/home/operator/Documents',
      context: posix,
    );

    expect(
      path,
      posix.join(
        '/home/operator/Documents',
        CockpitStoragePaths.storageSubdirectory,
        'state',
      ),
    );
  });

  test(
    'legacy candidates prefer Documents and de-duplicate normalized roots',
    () {
      final windows = p.Context(style: p.Style.windows);

      final candidates = CockpitStoragePaths.legacyDirectoriesFromRoots(
        documentsRoot: r'C:\Users\operator\Documents\.',
        applicationSupportRoot: r'C:\Users\operator\Documents',
        context: windows,
      );

      expect(candidates, hasLength(1));
      expect(
        candidates.single,
        windows.join(
          r'C:\Users\operator\Documents',
          CockpitStoragePaths.storageSubdirectory,
        ),
      );
    },
  );
}
