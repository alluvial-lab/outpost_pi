/// Compare simplified `x.y.z` semantic versions numerically by component.
///
/// Prerelease and build suffixes such as `-beta` and `+1` are ignored. Only
/// the first three numeric components participate; missing and non-numeric
/// components count as zero, so `1.2` equals `1.2.0`.
library;

List<int> _parse(String v) {
  // Discard prerelease and build metadata after the first `-` or `+`.
  final core = v.trim().split(RegExp(r'[-+]')).first;
  final parts = core.split('.');
  return List<int>.generate(3, (i) {
    if (i >= parts.length) return 0;
    return int.tryParse(parts[i].trim()) ?? 0;
  });
}

/// Compare [a] and [b] using the module's simplified semantic-version rules.
///
/// Return `-1` when [a] is lower, `0` when they are equivalent, and `1` when
/// [a] is higher.
int compareSemver(String a, String b) {
  final pa = _parse(a);
  final pb = _parse(b);
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i] < pb[i] ? -1 : 1;
  }
  return 0;
}

/// Report whether [candidate] is strictly newer than [current].
bool isNewerVersion(String candidate, String current) =>
    compareSemver(candidate, current) > 0;
