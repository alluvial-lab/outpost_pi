import 'package:app/ui/chat/ctx_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatCtxMax', () {
    test('formats common context ceilings', () {
      expect(formatCtxMax(1000000), '1m');
      expect(formatCtxMax(272000), '272k');
    });

    test('keeps sub-thousand ceilings raw', () {
      expect(formatCtxMax(999), '999');
    });
  });

  group('formatCtxTelemetryLine', () {
    test('combines branch, percentage, and ceiling', () {
      expect(
        formatCtxTelemetryLine(branch: 'main', percent: 92, maxTokens: 1000000),
        'main · 92% of 1m',
      );
    });

    test('omits missing branch and ceiling independently', () {
      expect(formatCtxTelemetryLine(percent: 42, maxTokens: null), '42%');
      expect(formatCtxTelemetryLine(branch: 'main', percent: 42), 'main · 42%');
    });

    test('returns empty for a missing percentage', () {
      expect(
        formatCtxTelemetryLine(branch: 'main', percent: null, maxTokens: 1000),
        isEmpty,
      );
    });

    test('preserves the pressure boundary in the formatted value', () {
      expect(formatCtxTelemetryLine(percent: 84), '84%');
      expect(formatCtxTelemetryLine(percent: 85), '85%');
    });
  });
}
