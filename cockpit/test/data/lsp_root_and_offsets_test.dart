import 'dart:io';

import 'package:cockpit/app/core/data/lsp/project_root_finder.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/ui/widgets/code_highlight.dart';
import 'package:flutter_test/flutter_test.dart';

String join(String a, String b) => '$a${Platform.pathSeparator}$b';

LspDiagnostic diag(
  int sl,
  int sc,
  int el,
  int ec, [
  LspSeverity sev = LspSeverity.error,
]) {
  return LspDiagnostic(
    range: LspRange(LspPosition(sl, sc), LspPosition(el, ec)),
    severity: sev,
    message: 'x',
  );
}

void main() {
  group('diagnosticRangesFor (line/char UTF-16 → offset)', () {
    test('range on a middle line', () {
      const text = 'abc\ndefg\nhij'; // Line 1 starts at 4.
      final r = diagnosticRangesFor(text, [diag(1, 1, 1, 3)]);
      expect(r, hasLength(1));
      expect(r.first.start, 5); // 4 + 1
      expect(r.first.end, 7); // 4 + 3
    });

    test('zero width becomes 1 character', () {
      const text = 'abc';
      final r = diagnosticRangesFor(text, [diag(0, 1, 0, 1)]);
      expect(r.first.start, 1);
      expect(r.first.end, 2);
    });

    test('character beyond the line end is clamped to the content end', () {
      const text =
          'ab\ncd'; // Line 0 content = 'ab'; it ends at offset 2 (the \n).
      final r = diagnosticRangesFor(text, [diag(0, 99, 0, 99)]);
      // Start clamped to 2; zero width → end 3, within length 5.
      expect(r.first.start, 2);
    });

    test('out-of-range line falls at the end of the text', () {
      const text = 'abc';
      final r = diagnosticRangesFor(text, [diag(9, 0, 9, 1)]);
      // start=end=text.length → zero width expands, then clamps → discarded.
      expect(r, isEmpty);
    });

    test('emoji (surrogate pair) counts as 2 code units, as in LSP', () {
      const text = '🚀ab'; // '🚀' = 2 code units (0,1); 'a'=2, 'b'=3
      final r = diagnosticRangesFor(text, [diag(0, 2, 0, 3)]);
      expect(r.first.start, 2);
      expect(r.first.end, 3);
    });
  });

  group('ProjectRootFinder', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('lsp_root_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('finds the root using an exact marker (monorepo)', () {
      // tmp/pkg/pubspec.yaml; file at tmp/pkg/lib/main.dart.
      final pkg = Directory(join(tmp.path, 'pkg'))..createSync();
      File(join(pkg.path, 'pubspec.yaml')).writeAsStringSync('name: x');
      final lib = Directory(join(pkg.path, 'lib'))..createSync();
      final file = join(lib.path, 'main.dart');

      final root = const ProjectRootFinder().findRoot(file, ['pubspec.yaml']);
      expect(root, pkg.path);
    });

    test('chooses the nearest root (nested package)', () {
      // tmp/pubspec.yaml AND tmp/inner/pubspec.yaml → a file in inner uses inner.
      File(join(tmp.path, 'pubspec.yaml')).writeAsStringSync('name: outer');
      final inner = Directory(join(tmp.path, 'inner'))..createSync();
      File(join(inner.path, 'pubspec.yaml')).writeAsStringSync('name: inner');
      final file = join(inner.path, 'a.dart');

      final root = const ProjectRootFinder().findRoot(file, ['pubspec.yaml']);
      expect(root, inner.path);
    });

    test('suffix marker (*.csproj)', () {
      File(join(tmp.path, 'App.csproj')).writeAsStringSync('<Project/>');
      final file = join(tmp.path, 'Program.cs');
      final root = const ProjectRootFinder().findRoot(file, ['*.csproj']);
      expect(root, tmp.path);
    });

    test('returns null without a marker', () {
      final file = join(tmp.path, 'orphan.dart');
      final root = const ProjectRootFinder().findRoot(file, ['pubspec.yaml']);
      expect(root, isNull);
    });
  });
}
