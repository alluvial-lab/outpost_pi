/// Humanize a raw token ceiling for compact context telemetry.
///
/// Exact-million ceilings use `m`, exact-thousand ceilings use `k`, and
/// smaller values remain raw so the formatter never hides a small limit.
String formatCtxMax(int tokens) {
  if (tokens < 1000) return '$tokens';
  if (tokens >= 1000000) {
    final millions = tokens / 1000000;
    return _formatCtxUnit(millions, 'm');
  }
  final thousands = tokens / 1000;
  return _formatCtxUnit(thousands, 'k');
}

String _formatCtxUnit(double value, String suffix) {
  final rounded = value.roundToDouble();
  if (value == rounded) return '${rounded.toInt()}$suffix';
  return '${value.toStringAsFixed(1)}$suffix';
}

/// Build the compact branch and context-usage line shown in the chat header.
///
/// Returns an empty string when [percent] is unavailable. A missing branch or
/// context ceiling omits only that segment; the usage percentage remains.
String formatCtxTelemetryLine({
  String? branch,
  required int? percent,
  int? maxTokens,
}) {
  if (percent == null) return '';
  final parts = <String>[];
  final normalizedBranch = branch?.trim();
  if (normalizedBranch != null && normalizedBranch.isNotEmpty) {
    parts.add(normalizedBranch);
  }
  final usage = maxTokens == null
      ? '$percent%'
      : '$percent% of ${formatCtxMax(maxTokens)}';
  parts.add(usage);
  return parts.join(' · ');
}
