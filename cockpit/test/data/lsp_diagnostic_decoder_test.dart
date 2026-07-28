import 'package:cockpit/app/core/data/lsp/lsp_diagnostic_decoder.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const decoder = LspDiagnosticDecoder();

  test('decodes a publication into typed diagnostics', () {
    final batch = decoder.decodePublishDiagnostics(<String, Object?>{
      'uri': 'file:///main.dart',
      'diagnostics': <Object?>[
        <String, Object?>{
          'range': <String, Object?>{
            'start': <String, Object?>{'line': 2, 'character': 3},
            'end': <String, Object?>{'line': 2, 'character': 8},
          },
          'severity': 2,
          'message': '  unused value  ',
          'source': 'analyzer',
          'code': 'unused_local_variable',
        },
      ],
    });

    expect(batch, isNotNull);
    final diagnostic = batch!.diagnostics.single;
    expect(diagnostic.range.start.line, 2);
    expect(diagnostic.range.start.character, 3);
    expect(diagnostic.range.end.character, 8);
    expect(diagnostic.severity, LspSeverity.warning);
    expect(diagnostic.message, 'unused value');
    expect(diagnostic.source, 'analyzer');
    expect(diagnostic.code, 'unused_local_variable');
  });

  test('preserves scalar fallbacks at the boundary', () {
    final diagnostic = decoder.decodeDiagnostic(<String, Object?>{
      'range': <String, Object?>{
        'start': <String, Object?>{},
        'end': <String, Object?>{'line': 'bad', 'character': null},
      },
      'severity': 99,
      'message': 42,
      'source': 42,
      'code': 7,
    });

    expect(diagnostic, isNotNull);
    expect(diagnostic!.range.start.line, 0);
    expect(diagnostic.range.start.character, 0);
    expect(diagnostic.severity, LspSeverity.error);
    expect(diagnostic.message, isEmpty);
    expect(diagnostic.source, isNull);
    expect(diagnostic.code, isNull);
  });

  test('rejects malformed ranges and skips non-map diagnostics', () {
    final batch = decoder.decodePublishDiagnostics(<String, Object?>{
      'uri': 'file:///main.dart',
      'diagnostics': <Object?>[
        <String, Object?>{
          'range': <String, Object?>{
            'start': <String, Object?>{'line': 0},
            'end': 'not a position',
          },
        },
        'not a diagnostic',
      ],
    });

    expect(batch, isNotNull);
    expect(batch!.diagnostics, isEmpty);
    expect(decoder.decodePublishDiagnostics('not params'), isNull);
  });

  test('valid params without diagnostics emits an empty batch', () {
    final batch = decoder.decodePublishDiagnostics(<String, Object?>{
      'uri': 'file:///main.dart',
    });

    expect(batch, isNotNull);
    expect(batch!.diagnostics, isEmpty);
  });
}
