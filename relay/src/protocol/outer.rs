use std::sync::OnceLock;

pub use crate::protocol::generated::limits::{
    RELAY_DEFAULT_MAX_DECODED_BYTES, RELAY_MAX_FRAME_OVERHEAD_BYTES, RELAY_MAX_PRE_AUTH_FRAME_BYTES,
};
pub use crate::protocol::generated::outer::OuterEnvelope;

impl OuterEnvelope {
    /// Serializes the generated outer envelope back to JSON for forwarding.
    ///
    /// Keep this tiny adapter next to the parse/size boundary so callers do
    /// not grow handwritten mirrors of the generated wire type. `ct` remains
    /// an opaque string; serialization never decodes or inspects it.
    pub fn to_json_string(&self) -> String {
        serde_json::to_string(self).expect("OuterEnvelope serialisation is infallible")
    }
}

/// Environment variable that overrides the outer-envelope limit in whole MiB.
pub const MAX_CT_ENV: &str = "RELAY_MAX_CT_MIB";

/// Default limit: 4 MiB of base64-decoded payload. It was historically a
/// fixed 1 MiB, but images pass through double base64 (inner `data` plus outer
/// `ct` ≈ 1.333× the raw JPEG), so 1 MiB silently dropped any image above
/// roughly 768 KB and left the app stuck at "sending…". Four MiB provides
/// headroom over the app compression cap (roughly 1.5 MB, 2 MB estimated).
pub const DEFAULT_MAX_CT_MIB: usize = RELAY_DEFAULT_MAX_DECODED_BYTES / (1024 * 1024);

/// Bounded JSON/routing overhead allowed beyond an encoded `ct` payload.
pub const MAX_FRAME_OVERHEAD_BYTES: usize = RELAY_MAX_FRAME_OVERHEAD_BYTES;

/// Maximum UTF-8 bytes accepted for one unauthenticated hello/auth message.
pub const MAX_PRE_AUTH_FRAME_BYTES: usize = RELAY_MAX_PRE_AUTH_FRAME_BYTES;

/// Effective outer-envelope limit in bytes. Read **once** from [`MAX_CT_ENV`]
/// (in MiB) on the first call and memoized. An absent or invalid value
/// (non-integer, zero, or empty) falls back to 4 MiB and never panics on a
/// production configuration path.
pub fn max_ct_bytes() -> usize {
    static MAX_CT_BYTES: OnceLock<usize> = OnceLock::new();
    *MAX_CT_BYTES.get_or_init(|| {
        let mib = std::env::var(MAX_CT_ENV)
            .ok()
            .and_then(|s| s.trim().parse::<usize>().ok())
            .filter(|&n| n > 0)
            .unwrap_or(DEFAULT_MAX_CT_MIB);
        mib.saturating_mul(1024 * 1024)
    })
}

/// Maximum complete WebSocket message size for the configured decoded payload
/// ceiling plus bounded JSON/routing overhead.
pub fn max_ws_message_bytes() -> usize {
    let encoded = max_ct_bytes()
        .saturating_add(2)
        .checked_div(3)
        .unwrap_or(usize::MAX)
        .saturating_mul(4);
    encoded.saturating_add(MAX_FRAME_OVERHEAD_BYTES)
}

/// Reports malformed outer envelopes and ciphertexts above the configured limit.
#[derive(Debug, thiserror::Error)]
pub enum ParseError {
    #[error("invalid json: {0}")]
    InvalidJson(#[from] serde_json::Error),
    #[error("payload too large: {0} bytes (max {1})")]
    TooLarge(usize, usize),
}

/// Parses one JSONL line as an outer envelope and validates its `ct` size
/// against [`max_ct_bytes`]. The relay never decodes `ct`; it estimates the
/// payload size from the base64 string length and trailing standard padding.
///
/// # Errors
///
/// Returns [`ParseError::InvalidJson`] when `line` is not a valid outer
/// envelope, or [`ParseError::TooLarge`] when the estimated ciphertext size
/// exceeds the configured limit.
pub fn parse_line(line: &str) -> Result<OuterEnvelope, ParseError> {
    parse_line_with_max(line, max_ct_bytes())
}

/// Testable [`parse_line`] core with an injected limit, so tests exercise the
/// boundary without mutating the global environment variable or racing the
/// memoized [`OnceLock`].
pub(crate) fn parse_line_with_max(
    line: &str,
    max_ct_bytes: usize,
) -> Result<OuterEnvelope, ParseError> {
    let env: OuterEnvelope = serde_json::from_str(line)?;
    let padding = env
        .ct
        .as_bytes()
        .iter()
        .rev()
        .take(2)
        .take_while(|&&byte| byte == b'=')
        .count();
    let estimated = env.ct.len().saturating_mul(3) / 4;
    let estimated = estimated.saturating_sub(padding);
    if estimated > max_ct_bytes {
        return Err(ParseError::TooLarge(estimated, max_ct_bytes));
    }
    Ok(env)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_missing_room() {
        let line = r#"{"peer":"abc","ct":"AAA="}"#;
        assert!(matches!(parse_line(line), Err(ParseError::InvalidJson(_))));
    }

    #[test]
    fn rejects_unknown_outer_field() {
        let line = r#"{"peer":"abc","room":"main","ct":"AAA=","unexpected":"opaque"}"#;
        assert!(matches!(parse_line(line), Err(ParseError::InvalidJson(_))));
    }

    #[test]
    fn parses_envelope_with_room() {
        let line = r#"{"peer":"abc","room":"aB12CD34eF56","ct":"AAA="}"#;
        let env = parse_line(line).unwrap();
        assert_eq!(env.room, "aB12CD34eF56");
    }

    #[test]
    fn preserves_opaque_ct_that_mentions_session_id() {
        let ct = "eyJzZXNzaW9uX2lkIjoib3BhcXVlIiwidGV4dCI6ImhlbGxvIn0=";
        let line = format!(r#"{{"peer":"abc","room":"main","ct":"{}"}}"#, ct);
        let env = parse_line(&line).unwrap();
        assert_eq!(env.ct, ct);
    }

    #[test]
    fn rejects_too_large() {
        // 12 MiB of "A" → estimated 9 MiB, above the 4 MiB default.
        // (It was previously 2 MiB → 1.5 MiB estimated, which now passes.)
        let big = "A".repeat(12 * 1024 * 1024);
        let line = format!(r#"{{"peer":"abc","room":"main","ct":"{}"}}"#, big);
        assert!(matches!(parse_line(&line), Err(ParseError::TooLarge(..))));
    }

    #[test]
    fn accepts_padded_payloads_at_non_divisible_boundaries() {
        let four_bytes = r#"{"peer":"abc","room":"main","ct":"AQIDBA=="}"#;
        assert!(parse_line_with_max(four_bytes, 4).is_ok());

        let five_bytes = r#"{"peer":"abc","room":"main","ct":"AQIDBAU="}"#;
        assert!(parse_line_with_max(five_bytes, 5).is_ok());
        assert!(matches!(
            parse_line_with_max(five_bytes, 4),
            Err(ParseError::TooLarge(5, 4))
        ));
    }

    #[test]
    fn accepts_exact_four_mib_decoded_boundary_and_rejects_next_byte() {
        let max = DEFAULT_MAX_CT_MIB * 1024 * 1024;
        let encoded_len = max.div_ceil(3) * 4;

        let exact_ct = format!("{}==", "A".repeat(encoded_len - 2));
        let exact = format!(r#"{{"peer":"abc","room":"main","ct":"{exact_ct}"}}"#);
        assert!(parse_line_with_max(&exact, max).is_ok());

        let over_ct = format!("{}=", "A".repeat(encoded_len - 1));
        let over = format!(r#"{{"peer":"abc","room":"main","ct":"{over_ct}"}}"#);
        assert!(matches!(
            parse_line_with_max(&over, max),
            Err(ParseError::TooLarge(estimated, limit))
                if estimated == max + 1 && limit == max
        ));
    }

    #[test]
    fn accepts_two_mb_payload_under_default() {
        // Image-bug regression: 3 MiB of base64 → roughly 2.25 MiB estimated.
        // The former 1 MiB limit silently dropped this and left the app stuck
        // at "sending…"; it must pass under the current 4 MiB default.
        let img = "A".repeat(3 * 1024 * 1024);
        let line = format!(r#"{{"peer":"abc","room":"main","ct":"{}"}}"#, img);
        let env = parse_line(&line).expect("≈2 MB payload must pass under 4 MiB default");
        assert_eq!(env.peer, "abc");
    }

    #[test]
    fn default_max_ct_bytes_is_four_mib() {
        // Without RELAY_MAX_CT_MIB in the test environment, the effective limit is 4 MiB.
        assert_eq!(max_ct_bytes(), DEFAULT_MAX_CT_MIB * 1024 * 1024);
        assert_eq!(max_ct_bytes(), 4 * 1024 * 1024);
        assert_eq!(max_ws_message_bytes(), 5_657_944);
    }

    #[test]
    fn injected_max_overrides_limit() {
        // Test the override through the injected-limit core without mutating
        // the global environment or racing the memoized OnceLock in parallel tests.
        // Roughly 2.25 MiB estimated: rejected by a 1 MiB limit, accepted by 4 MiB.
        let payload = "A".repeat(3 * 1024 * 1024);
        let line = format!(r#"{{"peer":"abc","room":"main","ct":"{}"}}"#, payload);

        assert!(matches!(
            parse_line_with_max(&line, 1024 * 1024),
            Err(ParseError::TooLarge(..))
        ));
        assert!(parse_line_with_max(&line, 4 * 1024 * 1024).is_ok());
    }

    #[test]
    fn rejects_invalid_json() {
        assert!(matches!(
            parse_line("not json at all"),
            Err(ParseError::InvalidJson(_))
        ));
    }
}
