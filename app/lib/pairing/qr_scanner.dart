import 'dart:convert';

const kPairLinkOrigin = 'https://outpost-pi.kevoun.com';
const kPairLinkPath = '/pair';
const kPairLinkPrefix = '$kPairLinkOrigin$kPairLinkPath#';

// QR/App Link format:
//   https://outpost-pi.kevoun.com/pair#t=<base64url>&epk=<base64url>&n=<name>[&r=<url>][&rm=<roomId>]
//
// Parameters stay in the fragment so a browser fallback never sends the
// enrollment capability to the site or its access logs.
//
// Fields:
//   t   — ephemeral token (16 bytes, base64url), single-use, valid for 60s
//   epk — Pi Ed25519 public key (32 bytes), the relay's unique peer ID
//   n   — session name (max 80 chars)
//   r   — relay WebSocket URL (OPTIONAL since plan 14: the app uses its own
//         configured relay; legacy QR codes that carry `r` are tolerated
//         and trigger a relay-change modal when the value mismatches the
//         user's configured relay).
//   rm  — Pi-side room id this QR was generated FROM (plan 17 fix —
//         lets the app address the right cwd-session on the first
//         pair_request; without it the relay drops with
//         "dest (peer, room) not found"). Optional; legacy QRs without
//         `rm` fall back to `'main'` during pair_request and rely on
//         subscribe_rooms-based discovery afterwards.

/// Hold the validated fields extracted from one Outpost-Pi pairing QR URI.
class QrPairPayload {
  final String token;
  final String epk; // base64url Ed25519 — relay peer ID
  /// Optional legacy relay URL embedded in the QR. `null` for new QRs.
  /// Use `pair_request_flow` to detect mismatch vs `Preferences.relayUrl`.
  final String? relayUrl;
  final String sessionName;

  /// Plan 17 fix: Pi-side room id (cwd-session). Used as the outer
  /// envelope's `room` on pair_request so the relay can route to the
  /// right Pi-WS. `null` for pre-plan-17 QRs — caller must fall back to
  /// `'main'` and discover the real room id via subscribe_rooms.
  final String? roomId;

  const QrPairPayload({
    required this.token,
    required this.epk,
    required this.sessionName,
    this.relayUrl,
    this.roomId,
  });

  /// Parse and validate an Outpost-Pi pairing URI at the untrusted QR boundary.
  ///
  /// Tolerates common paste artifacts — surrounding whitespace, trailing
  /// newlines, and wrapping quote characters — so a pasted pairing code is
  /// not silently rejected for formatting alone. Returns `null` for a wrong
  /// scheme, malformed encoding, or a token/public key with an invalid byte
  /// length; callers must not open a transport first.
  static QrPairPayload? tryParse(String raw) {
    // Normalize paste artifacts: trim whitespace/newlines and strip a single
    // pair of surrounding quotes that a terminal copy or message app may add.
    var input = raw.trim();
    if (input.length >= 2) {
      final first = input[0];
      final last = input[input.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        input = input.substring(1, input.length - 1).trim();
      }
    }
    try {
      final uri = Uri.parse(input);
      if (uri.scheme != 'https' ||
          uri.host != 'outpost-pi.kevoun.com' ||
          uri.path != kPairLinkPath ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          uri.hasQuery ||
          uri.fragment.isEmpty) {
        return null;
      }
      final parameters = Uri.splitQueryString(uri.fragment);
      final t = parameters['t'];
      final epk = parameters['epk'];
      final r = parameters['r']; // legacy/optional
      final n = parameters['n'];
      final rm = parameters['rm']; // plan 17 — Pi-side room
      // r is no longer required — plan 14 dropped it from the canonical
      // contract. Legacy QRs continue to include it; we capture it for
      // mismatch detection but don't reject when absent.
      // rm is optional too — legacy pi-extension didn't emit it, and
      // the app falls back to 'main' / discovery in that case.
      if (t == null || epk == null || n == null) return null;
      if (base64Url.decode(_pad(t)).length != 16) return null;
      if (base64Url.decode(_pad(epk)).length != 32) return null;
      return QrPairPayload(
        token: t,
        epk: epk,
        sessionName: n,
        relayUrl: (r != null && r.isNotEmpty) ? r : null,
        roomId: (rm != null && rm.isNotEmpty) ? rm : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Decode the validated Pi public key for cryptographic or transport setup.
  List<int> get epkBytes => base64Url.decode(_pad(epk));

  static String _pad(String s) {
    final p = (4 - s.length % 4) % 4;
    return s + '=' * p;
  }
}
