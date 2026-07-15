import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/file_system_mutator_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileSystemMutatorImpl', () {
    const mutator = FileSystemMutatorImpl();
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ck_fsm');
    });
    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('createFile creates an empty file', () async {
      final path = '${dir.path}/novo.txt';
      final r = await mutator.createFile(path);
      expect(r.isSuccess, isTrue);
      expect(File(path).existsSync(), isTrue);
      expect(File(path).readAsStringSync(), isEmpty);
    });

    test('createFile fails if the file already exists', () async {
      final path = '${dir.path}/dup.txt';
      File(path).writeAsStringSync('x');
      final r = await mutator.createFile(path);
      expect(r.isFailure, isTrue);
    });

    test('createDirectory creates a folder', () async {
      final path = '${dir.path}/sub';
      final r = await mutator.createDirectory(path);
      expect(r.isSuccess, isTrue);
      expect(Directory(path).existsSync(), isTrue);
    });

    test('rename moves the file to the new name', () async {
      final from = '${dir.path}/a.txt';
      final to = '${dir.path}/b.txt';
      File(from).writeAsStringSync('conteudo');
      final r = await mutator.rename(from, to);
      expect(r.isSuccess, isTrue);
      expect(File(from).existsSync(), isFalse);
      expect(File(to).readAsStringSync(), 'conteudo');
    });

    test('rename renames a folder (including its contents)', () async {
      final from = '${dir.path}/old';
      final to = '${dir.path}/new';
      Directory(from).createSync();
      File('$from/inner.txt').writeAsStringSync('hi');
      final r = await mutator.rename(from, to);
      expect(r.isSuccess, isTrue);
      expect(Directory(from).existsSync(), isFalse);
      expect(File('$to/inner.txt').readAsStringSync(), 'hi');
    });

    test('rename fails if the destination already exists', () async {
      final from = '${dir.path}/x.txt';
      final to = '${dir.path}/y.txt';
      File(from).writeAsStringSync('1');
      File(to).writeAsStringSync('2');
      final r = await mutator.rename(from, to);
      expect(r.isFailure, isTrue);
    });

    test('moveToTrash succeeds for a nonexistent path (idempotent)', () async {
      final r = await mutator.moveToTrash('${dir.path}/ghost.txt');
      expect(r.isSuccess, isTrue);
    });

    test('moveToTrash removes the file from its original path', () async {
      // useSystemTrash: false → permanent deletion instead of sending the file
      // to the real macOS Trash (otherwise every `flutter test` pollutes it).
      const fileMutator = FileSystemMutatorImpl(useSystemTrash: false);
      final path = '${dir.path}/trash-me.txt';
      File(path).writeAsStringSync('bye');
      final r = await fileMutator.moveToTrash(path);
      expect(r.isSuccess, isTrue);
      expect(File(path).existsSync(), isFalse);
    });
  });
}
