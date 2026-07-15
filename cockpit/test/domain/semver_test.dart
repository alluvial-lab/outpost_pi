import 'package:cockpit/app/cockpit/domain/value_objects/semver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareSemver', () {
    test('returns 0 for equivalent versions', () {
      expect(compareSemver('1.0.0', '1.0.0'), 0);
      expect(compareSemver('1.2', '1.2.0'), 0); // A missing component is zero.
    });

    test('compares each component numerically rather than lexically', () {
      expect(compareSemver('1.0.10', '1.0.9'), 1); // 10 is greater than 9.
      expect(compareSemver('1.0.9', '1.0.10'), -1);
      expect(compareSemver('2.0.0', '1.9.9'), 1);
      expect(compareSemver('1.1.0', '1.0.99'), 1);
    });

    test('ignores prerelease and build metadata', () {
      expect(compareSemver('1.0.0-beta', '1.0.0'), 0);
      expect(compareSemver('1.0.1+5', '1.0.0'), 1);
    });

    test('treats non-numeric components as zero', () {
      expect(compareSemver('1.x.0', '1.0.0'), 0);
    });
  });

  group('isNewerVersion', () {
    test('returns true only when the candidate is strictly newer', () {
      expect(isNewerVersion('1.1.0', '1.0.0'), isTrue);
      expect(isNewerVersion('1.0.0', '1.0.0'), isFalse); // Equal.
      expect(isNewerVersion('0.9.0', '1.0.0'), isFalse); // Lower.
      expect(isNewerVersion('1.0.10', '1.0.2'), isTrue);
    });
  });
}
