/// Compare simple `x.y.z` semver versions numerically by component.
///
/// Pre-release and build suffixes (`-beta`, `+1`) are ignored; only the first
/// three numeric components participate. Missing components count as zero
/// (`1.2` == `1.2.0`), as do non-numeric components. This mirrors Cockpit's
/// implementation so the app reads the same `latest.json` schema.
library;

List<int> _parse(String v) {
  // Remove everything after `-` or `+` (pre-release / build metadata).
  final core = v.trim().split(RegExp(r'[-+]')).first;
  final parts = core.split('.');
  return List<int>.generate(3, (i) {
    if (i >= parts.length) return 0;
    return int.tryParse(parts[i].trim()) ?? 0;
  });
}

/// Compare [a] and [b], returning `-1`, `0`, or `1`.
int compareSemver(String a, String b) {
  final pa = _parse(a);
  final pb = _parse(b);
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i] < pb[i] ? -1 : 1;
  }
  return 0;
}

/// Report whether [candidate] is newer than [current].
bool isNewerVersion(String candidate, String current) =>
    compareSemver(candidate, current) > 0;
