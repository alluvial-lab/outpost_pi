import 'package:cockpit/app/cockpit/domain/validators/file_name_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileNameValidator', () {
    test('rejects both platform path separators', () {
      expect(
        FileNameValidator.validate('/repo', r'..\target').isValid,
        isFalse,
      );
      expect(
        FileNameValidator.validate('/repo', 'nested/name').isValid,
        isFalse,
      );
    });

    test('rejects drive and UNC-style names', () {
      expect(
        FileNameValidator.validate('/repo', r'C:\target').isValid,
        isFalse,
      );
      expect(
        FileNameValidator.validate('/repo', r'\\server\share').isValid,
        isFalse,
      );
      expect(FileNameValidator.validate('/repo', 'C:target').isValid, isFalse);
    });

    test('rejects control characters', () {
      expect(
        FileNameValidator.validate('/repo', 'safe\u0000name').isValid,
        isFalse,
      );
      expect(
        FileNameValidator.validate('/repo', 'safe\u007fname').isValid,
        isFalse,
      );
    });

    test('normalizes the final path and keeps it below its parent', () {
      final result = FileNameValidator.validate(r'C:\repo\folder', 'file.txt');
      expect(result.isValid, isTrue);
      expect(result.path, 'C:/repo/folder/file.txt');
      expect(
        FileNameValidator.validate(r'C:\', 'file.txt').path,
        'C:/file.txt',
      );
    });
  });
}
