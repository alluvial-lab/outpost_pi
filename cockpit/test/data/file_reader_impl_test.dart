import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/file_reader_impl.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const reader = FileReaderImpl();

  group('FileReaderImpl — A/V detection (plan 46)', () {
    test('video → FileViewVideo (path only, without disk access)', () async {
      const exts = ['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v', 'wmv', 'flv'];
      for (final ext in exts) {
        // Intentionally nonexistent path: A/V resolves by extension BEFORE
        // any read, so it cannot depend on the file existing.
        final path = '/tmp/does-not-exist-46/clip.$ext';
        final view = await reader.read(path);
        expect(view, isA<FileViewVideo>(), reason: '.$ext should be video');
        expect((view as FileViewVideo).path, path);
      }
    });

    test('audio → FileViewAudio (path only, without disk access)', () async {
      const exts = ['mp3', 'wav', 'aac', 'm4a', 'flac', 'ogg', 'opus'];
      for (final ext in exts) {
        final path = '/tmp/does-not-exist-46/track.$ext';
        final view = await reader.read(path);
        expect(view, isA<FileViewAudio>(), reason: '.$ext should be audio');
        expect((view as FileViewAudio).path, path);
      }
    });

    test('image remains FileViewImage (no regression)', () async {
      final view = await reader.read('/tmp/does-not-exist-46/pic.png');
      expect(view, isA<FileViewImage>());
    });

    test('unknown extension follows the existing path: nonexistent → '
        'FileViewUnsupported', () async {
      final view = await reader.read('/tmp/does-not-exist-46/file.xyz');
      expect(view, isA<FileViewUnsupported>());
    });

    test('unknown extension with real text → FileViewText', () async {
      final dir = await Directory.systemTemp.createTemp('ck_fr_test');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}/notes.log')..writeAsStringSync('hello world');
      final view = await reader.read(f.path);
      expect(view, isA<FileViewText>());
      expect((view as FileViewText).text, 'hello world');
    });

    test('write saves to disk and read returns the new content', () async {
      final dir = await Directory.systemTemp.createTemp('ck_fr_write');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}/main.dart')..writeAsStringSync('old');
      final ok = await reader.write(f.path, 'void main() {}');
      expect(ok, isTrue);
      expect(f.readAsStringSync(), 'void main() {}');
      final view = await reader.read(f.path);
      expect((view as FileViewText).text, 'void main() {}');
    });

    test('svg → FileViewSvg (source + path, editable)', () async {
      final dir = await Directory.systemTemp.createTemp('ck_fr_svg');
      addTearDown(() => dir.delete(recursive: true));
      const svg = '<svg xmlns="http://www.w3.org/2000/svg"></svg>';
      final f = File('${dir.path}/icon.svg')..writeAsStringSync(svg);
      final view = await reader.read(f.path);
      expect(view, isA<FileViewSvg>());
      expect((view as FileViewSvg).text, svg);
      expect(view.path, f.path);
    });

    test('write to an invalid path (nonexistent dir) → false', () async {
      final ok = await reader.write('/tmp/no-such-dir-99/x.txt', 'data');
      expect(ok, isFalse);
    });
  });
}
