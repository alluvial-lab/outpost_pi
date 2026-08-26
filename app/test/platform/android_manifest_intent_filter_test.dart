import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest routes outpostpi pair links to the app activity', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final viewFilters = RegExp(
      r'<intent-filter>(.*?)</intent-filter>',
      dotAll: true,
    ).allMatches(manifest).map((match) => match.group(1)!).toList();
    final pairFilter = viewFilters.firstWhere(
      (filter) => filter.contains('android.intent.action.VIEW'),
      orElse: () => '',
    );

    expect(pairFilter, isNotEmpty);
    expect(pairFilter, contains('android.intent.category.DEFAULT'));
    expect(pairFilter, contains('android.intent.category.BROWSABLE'));
    expect(pairFilter, contains('android:scheme="outpostpi"'));
    expect(pairFilter, contains('android:host="pair"'));
  });
}
