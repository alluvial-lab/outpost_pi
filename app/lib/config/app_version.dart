import 'package:package_info_plus/package_info_plus.dart';

/// Read the running platform bundle's user-visible application version.
Future<String> loadAppVersion() async {
  final packageInfo = await PackageInfo.fromPlatform();
  return packageInfo.version;
}
