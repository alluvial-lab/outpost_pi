import 'package:cockpit/app/core/data/lsp/lsp_text_edit.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

LspTextEdit edit(int sl, int sc, int el, int ec, String newText) => LspTextEdit(
  range: LspRange(LspPosition(sl, sc), LspPosition(el, ec)),
  newText: newText,
);

void main() {
  group('parseTextEdits', () {
    test('parses a list from the wire', () {
      final r = parseTextEdits([
        {
          'range': {
            'start': {'line': 0, 'character': 0},
            'end': {'line': 0, 'character': 1},
          },
          'newText': 'X',
        },
      ]);
      expect(r, hasLength(1));
      expect(r.first.newText, 'X');
    });

    test('non-list input becomes empty', () {
      expect(parseTextEdits(null), isEmpty);
      expect(parseTextEdits('nope'), isEmpty);
    });
  });

  group('applyTextEdits', () {
    test('replaces a span within one line', () {
      const text = 'int x=1;';
      // Replace '=' (cols 5..6) with ' = '
      final out = applyTextEdits(text, [edit(0, 5, 0, 6, ' = ')]);
      expect(out, 'int x = 1;');
    });

    test('applies all non-overlapping edits regardless of order', () {
      const text = 'a=1;b=2;';
      final out = applyTextEdits(text, [
        edit(0, 1, 0, 2, ' = '), // First '='
        edit(0, 5, 0, 6, ' = '), // Second '='
      ]);
      expect(out, 'a = 1;b = 2;');
    });

    test('edit spanning lines (multiline reformatting)', () {
      const text = 'a{\n  x\n}';
      // Replace everything with the formatted version.
      final out = applyTextEdits(text, [edit(0, 0, 2, 1, 'a {\n  x\n}')]);
      expect(out, 'a {\n  x\n}');
    });

    test('empty list returns the text unchanged', () {
      expect(applyTextEdits('abc', const []), 'abc');
    });

    test('clamps a stale range without crashing', () {
      const text = 'abc';
      final out = applyTextEdits(text, [edit(99, 0, 99, 5, 'Z')]);
      // Position beyond the end → effective no-op (insertion at the end).
      expect(out, anyOf('abc', 'abcZ'));
    });
  });
}
