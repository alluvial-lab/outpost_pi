import 'package:app/config/app_version.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  test(
    'loads the user-visible version from platform package metadata',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'Outpost-Pi',
        packageName: 'dev.kevoun.outpostpi',
        version: '1.2.3',
        buildNumber: '45',
        buildSignature: '',
      );

      expect(await loadAppVersion(), '1.2.3');
    },
  );
}
