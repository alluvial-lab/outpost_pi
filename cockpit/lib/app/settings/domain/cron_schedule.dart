/// Preview the next local run of a standard five-field cron expression.
///
/// Supports numbers and `* , - /`; day-of-week accepts both 0 and 7 for Sunday.
/// Returns `null` for croner extensions such as seconds, `@daily`, `L`, `#`,
/// `?`, or `W`, allowing the UI to show "calculated on save". The server's
/// croner-derived `next_run` remains authoritative; this is only a local-time
/// estimate.
DateTime? nextCronRun(String expr, DateTime from) {
  final fields = expr.trim().split(RegExp(r'\s+'));
  if (fields.length != 5) return null;

  final minutes = _parseField(fields[0], 0, 59);
  final hours = _parseField(fields[1], 0, 23);
  final doms = _parseField(fields[2], 1, 31);
  final months = _parseField(fields[3], 1, 12);
  final dows = _parseField(fields[4], 0, 7);
  if (minutes == null ||
      hours == null ||
      doms == null ||
      months == null ||
      dows == null) {
    return null;
  }
  // Normalize day-of-week: 7 → 0 (Sunday).
  final dowSet = dows.map((d) => d == 7 ? 0 : d).toSet();

  final domRestricted = !_isFull(fields[2]);
  final dowRestricted = !_isFull(fields[4]);

  // Start at the next whole minute.
  var t = DateTime(
    from.year,
    from.month,
    from.day,
    from.hour,
    from.minute,
  ).add(const Duration(minutes: 1));

  // Search horizon: about 366 days in minutes; standard cron always matches.
  const maxIterations = 367 * 24 * 60;
  for (var i = 0; i < maxIterations; i++) {
    if (months.contains(t.month) &&
        hours.contains(t.hour) &&
        minutes.contains(t.minute) &&
        _dayMatches(t, doms, dowSet, domRestricted, dowRestricted)) {
      return t;
    }
    t = t.add(const Duration(minutes: 1));
  }
  return null;
}

bool _isFull(String field) => field.trim() == '*';

/// Apply Vixie cron day matching.
///
/// When both day-of-month and day-of-week are restricted, either may match. If
/// only one is restricted, that field controls the match; otherwise any day
/// matches.
bool _dayMatches(
  DateTime t,
  Set<int> doms,
  Set<int> dowSet,
  bool domRestricted,
  bool dowRestricted,
) {
  final cronDow = t.weekday % 7; // DateTime: Mon=1..Sun=7 → cron Sun=0..Sat=6
  final domHit = doms.contains(t.day);
  final dowHit = dowSet.contains(cronDow);
  if (domRestricted && dowRestricted) return domHit || dowHit;
  if (domRestricted) return domHit;
  if (dowRestricted) return dowHit;
  return true;
}

/// Parse a field into its allowed values, returning `null` when invalid.
Set<int>? _parseField(String field, int min, int max) {
  final out = <int>{};
  for (final rawPart in field.split(',')) {
    var part = rawPart.trim();
    if (part.isEmpty) return null;

    var step = 1;
    final slash = part.indexOf('/');
    if (slash >= 0) {
      step = int.tryParse(part.substring(slash + 1)) ?? -1;
      if (step <= 0) return null;
      part = part.substring(0, slash);
    }

    int lo;
    int hi;
    if (part == '*') {
      lo = min;
      hi = max;
    } else if (part.contains('-')) {
      final range = part.split('-');
      if (range.length != 2) return null;
      final a = int.tryParse(range[0]);
      final b = int.tryParse(range[1]);
      if (a == null || b == null) return null;
      lo = a;
      hi = b;
    } else {
      final v = int.tryParse(part);
      if (v == null) return null;
      lo = hi = v;
    }
    if (lo < min || hi > max || lo > hi) return null;
    for (var v = lo; v <= hi; v += step) {
      out.add(v);
    }
  }
  return out.isEmpty ? null : out;
}
