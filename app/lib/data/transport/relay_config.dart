// Relay endpoint resolution.
//
// The app uses one configured relay as its primary endpoint, with a retained
// pairing-record endpoint available as an ordered reconnect alternate. A
// stored `prefs.relayUrl` resolves to the primary relay; its absence is an
// explicit recoverable configuration state.
//
// Canonical scheme on storage is `http://` or `https://` — this is
// the form the user types and what we keep in Preferences. The WebSocket
// transport calls [toWsRelayUrl] right before opening the socket; the
// mesh HTTP client uses the URL as-is. The legacy `ws://` / `wss://`
// schemes are NOT accepted on input — the app is pre-release and
// historical persisted values get re-set by the user during the
// onboarding gate.
//
// `peer.relayUrl` remains legacy QR metadata and is used only as a reconnect
// alternate after the configured primary fails; pairing still resolves against
// the global configured relay.

import 'package:app/data/preferences/preferences.dart';

/// User-facing recovery message for every unconfigured-relay boundary.
const String kRelayNotConfiguredMessage =
    'Relay not configured. Set a relay in Settings and try again.';

/// Identify the source that produced a relay-resolution branch.
enum RelaySource { preferences, unconfigured }

/// Represent the explicit result of resolving relay configuration without I/O.
sealed class RelayResolution {
  const RelayResolution();
  RelaySource get source;
}

/// Carry the canonical user-configured HTTP(S) relay URL.
final class ConfiguredRelay extends RelayResolution {
  const ConfiguredRelay(this.url);

  final String url;

  @override
  RelaySource get source => RelaySource.preferences;
}

/// Signal that callers must surface configuration recovery instead of connecting.
final class UnconfiguredRelay extends RelayResolution {
  const UnconfiguredRelay();

  @override
  RelaySource get source => RelaySource.unconfigured;
}

/// Raised by I/O boundaries when a relay connection was requested without a
/// configured relay. Configuration is recoverable, so callers must surface
/// [kRelayNotConfiguredMessage] rather than retrying network I/O.
final class RelayNotConfiguredException implements Exception {
  const RelayNotConfiguredException();

  @override
  String toString() => kRelayNotConfiguredMessage;
}

/// User-facing message returned when [isValidRelayUrl] rejects a value.
/// Surfaced verbatim by Settings and Onboarding — keep stable for
/// localization later. Empty input gets a more generic message; the
/// ws/wss case is called out explicitly so the user understands the
/// app does the conversion internally.
const String kRelayUrlInvalidScheme =
    'Use http:// or https:// (not ws:// or wss:// — the app converts '
    'to WebSocket automatically).';

const String kRelayUrlInvalidGeneric =
    'Enter a valid URL starting with https:// (or http:// for local '
    'relays).';

/// Resolves the relay configuration without performing I/O.
///
/// A configured branch always carries the stored canonical `http(s)://` URL.
/// An absent preference stays observable as [UnconfiguredRelay] so each I/O
/// boundary can offer its appropriate recovery action instead of silently
/// connecting to an unrelated relay.
RelayResolution resolveRelayUrl(Preferences prefs) {
  final url = prefs.relayUrl;
  return url == null ? const UnconfiguredRelay() : ConfiguredRelay(url);
}

/// Return relay endpoints in preference order without duplicate wire URLs.
///
/// The configured relay is the primary endpoint. Legacy QR metadata retained on
/// a paired [PeerRecord] is supplied as an alternate so a tailnet/LAN path can
/// recover without changing the user's global setting.
List<String> orderedRelayUrls(String primary, Iterable<String> alternates) {
  final result = <String>[];
  final seen = <String>{};
  for (final candidate in <String>[primary, ...alternates]) {
    final value = candidate.trim();
    if (value.isEmpty) continue;
    final wireValue = toWsRelayUrl(value);
    if (seen.add(wireValue)) result.add(value);
  }
  return List<String>.unmodifiable(result);
}

/// Translates the canonical HTTP-form relay URL into the WebSocket
/// form expected by the underlying transport. `https://` → `wss://`,
/// `http://` → `ws://`. Pre-existing `ws(s)://` URLs (legacy QR
/// payloads, old peer records) pass through unchanged so the relay
/// mismatch check in `pair_request_flow` can still compare them.
String toWsRelayUrl(String url) {
  if (url.startsWith('https://')) return 'wss://${url.substring(8)}';
  if (url.startsWith('http://')) return 'ws://${url.substring(7)}';
  return url;
}

/// Validates a candidate relay URL the user typed into Settings or
/// the onboarding form.
///
/// Rules:
/// - Non-empty.
/// - Scheme must be `http://` or `https://`. Returns `false` (with the
///   ws/wss-specific reason via [relayUrlValidationMessage]) for the
///   legacy `ws://` / `wss://` schemes — the app converts internally.
/// - Must be parseable by `Uri.parse` AND yield a non-empty `host`.
bool isValidRelayUrl(String url) {
  if (url.isEmpty) return false;
  if (url.startsWith('ws://') || url.startsWith('wss://')) {
    return false;
  }
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    return false;
  }
  final Uri uri;
  try {
    uri = Uri.parse(url);
  } catch (_) {
    return false;
  }
  if (uri.host.isEmpty) return false;
  return true;
}

/// Returns the user-facing rejection message for [url]. Returns `null`
/// when the URL is valid. Distinguishes the ws/wss case (specific
/// hint about internal conversion) from generic invalid scheme /
/// malformed input.
String? relayUrlValidationMessage(String url) {
  if (url.isEmpty) return kRelayUrlInvalidGeneric;
  if (url.startsWith('ws://') || url.startsWith('wss://')) {
    return kRelayUrlInvalidScheme;
  }
  if (isValidRelayUrl(url)) return null;
  return kRelayUrlInvalidGeneric;
}
