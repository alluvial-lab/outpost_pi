import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _releaseCertificateFingerprint =
    '63:B8:F2:D5:DA:E7:3A:41:27:9A:46:79:9A:72:72:9C:B4:7D:C4:64:'
    '90:F3:B0:E4:92:30:D0:B9:72:4C:4C:5B';

void main() {
  test('Android exposes pairing only through an auto-verified HTTPS link', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final viewFilters =
        RegExp(r'<intent-filter([^>]*)>(.*?)</intent-filter>', dotAll: true)
            .allMatches(manifest)
            .where(
              (match) => match.group(2)!.contains('android.intent.action.VIEW'),
            );

    expect(viewFilters, hasLength(1));
    final pairFilter = viewFilters.single;
    expect(pairFilter.group(1), contains('android:autoVerify="true"'));
    expect(pairFilter.group(2), contains('android.intent.category.DEFAULT'));
    expect(pairFilter.group(2), contains('android.intent.category.BROWSABLE'));
    expect(pairFilter.group(2), contains('android:scheme="https"'));
    expect(
      pairFilter.group(2),
      contains('android:host="outpost-pi.kevoun.com"'),
    );
    expect(pairFilter.group(2), contains('android:path="/pair"'));
    expect(manifest, isNot(contains('android:scheme="outpostpi"')));
  });

  test('Digital Asset Links binds the pair domain to the release signer', () {
    final statements =
        jsonDecode(
              File(
                '../site/public/.well-known/assetlinks.json',
              ).readAsStringSync(),
            )
            as List<dynamic>;

    expect(statements, hasLength(1));
    final statement = statements.single as Map<String, dynamic>;
    expect(statement['relation'], [
      'delegate_permission/common.handle_all_urls',
    ]);
    final target = statement['target'] as Map<String, dynamic>;
    expect(target['namespace'], 'android_app');
    expect(target['package_name'], 'dev.kevoun.outpostpi');
    expect(target['sha256_cert_fingerprints'], [
      _releaseCertificateFingerprint,
    ]);
  });
}
