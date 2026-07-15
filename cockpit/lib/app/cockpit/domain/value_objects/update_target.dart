/// Carry the update target resolved during application bootstrap.
///
/// The current version, platform, package format, and architecture select the
/// correct manifest artifact. Register this value object in `cockpit_module`
/// so `UpdateViewModel` can use `.new` injection without four ambiguous
/// `String` dependencies.
class UpdateTarget {
  /// Create a target from values resolved during application bootstrap.
  const UpdateTarget({
    required this.version,
    required this.platform,
    required this.format,
    required this.arch,
    this.selfUpdateFeedUrl,
  });

  /// The running application version reported by `package_info`.
  final String version;

  /// The manifest platform key: `macos`, `windows`, or `linux`.
  final String platform;

  /// The platform package format: `dmg`, `exe`, or `deb`, respectively.
  final String format;

  /// The artifact architecture: macOS uses `universal`, Windows uses `x64`,
  /// and Linux uses `arm64` or `x64`.
  final String arch;

  /// The native updater's appcast URL, when this platform supports one.
  ///
  /// macOS uses `appcast-macos.xml`, Windows uses `appcast-windows.xml`, and
  /// Linux leaves this `null` to use notification plus manual download.
  final String? selfUpdateFeedUrl;
}
