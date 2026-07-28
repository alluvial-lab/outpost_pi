pub use crate::protocol::generated::limits::{
    RELAY_DEFAULT_MAX_DECODED_BYTES, RELAY_MAX_FRAME_OVERHEAD_BYTES, RELAY_MAX_PRE_AUTH_FRAME_BYTES,
};
pub use crate::protocol::generated::outer::OuterEnvelope;

impl OuterEnvelope {
    /// Serialize the generated outer envelope without inspecting opaque `ct`.
    pub fn to_json_string(&self) -> String {
        serde_json::to_string(self).expect("OuterEnvelope serialisation is infallible")
    }
}

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

/// Parse outer envelopes using a composition-provided ciphertext ceiling.
#[derive(Debug, Clone, Copy)]
pub struct OuterEnvelopeParser {
    max_ct_bytes: usize,
}

impl OuterEnvelopeParser {
    /// Create a parser with an explicit decoded ciphertext ceiling.
    pub const fn new(max_ct_bytes: usize) -> Self {
        Self { max_ct_bytes }
    }

    /// Return the configured decoded ciphertext ceiling.
    pub const fn max_ct_bytes(&self) -> usize {
        self.max_ct_bytes
    }

    /// Return the raw WebSocket-message ceiling derived from the same limit.
    pub fn max_ws_message_bytes(&self) -> usize {
        let encoded = self
            .max_ct_bytes
            .saturating_add(2)
            .checked_div(3)
            .unwrap_or(usize::MAX)
            .saturating_mul(4);
        encoded.saturating_add(MAX_FRAME_OVERHEAD_BYTES)
    }

    /// Parse one JSONL line and enforce this parser's ciphertext ceiling.
    ///
    /// # Errors
    ///
    /// Returns [`ParseError::InvalidJson`] for malformed envelopes or
    /// [`ParseError::TooLarge`] when estimated ciphertext bytes exceed the
    /// configured limit.
    pub fn parse_line(&self, line: &str) -> Result<OuterEnvelope, ParseError> {
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
        if estimated > self.max_ct_bytes {
            return Err(ParseError::TooLarge(estimated, self.max_ct_bytes));
        }
        Ok(env)
    }
}

/// Reports malformed outer envelopes and ciphertexts above the configured limit.
#[derive(Debug, thiserror::Error)]
pub enum ParseError {
    #[error("invalid json: {0}")]
    InvalidJson(#[from] serde_json::Error),
    #[error("payload too large: {0} bytes (max {1})")]
    TooLarge(usize, usize),
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parser(max_ct_bytes: usize) -> OuterEnvelopeParser {
        OuterEnvelopeParser::new(max_ct_bytes)
    }

    #[test]
    fn rejects_missing_room() {
        let line = r#"{"peer":"abc","ct":"AAA="}"#;
        assert!(matches!(
            parser(4).parse_line(line),
            Err(ParseError::InvalidJson(_))
        ));
    }

    #[test]
    fn rejects_unknown_outer_field() {
        let line = r#"{"peer":"abc","room":"main","ct":"AAA=","unexpected":"opaque"}"#;
        assert!(matches!(
            parser(4).parse_line(line),
            Err(ParseError::InvalidJson(_))
        ));
    }

    #[test]
    fn parses_envelope_with_room() {
        let line = r#"{"peer":"abc","room":"aB12CD34eF56","ct":"AAA="}"#;
        let env = parser(4).parse_line(line).unwrap();
        assert_eq!(env.room, "aB12CD34eF56");
    }

    #[test]
    fn preserves_opaque_ct_that_mentions_session_id() {
        let ct = "eyJzZXNzaW9uX2lkIjoib3BhcXVlIiwidGV4dCI6ImhlbGxvIn0=";
        let line = format!(r#"{{"peer":"abc","room":"main","ct":"{}"}}"#, ct);
        let env = parser(1024).parse_line(&line).unwrap();
        assert_eq!(env.ct, ct);
    }

    #[test]
    fn accepts_padded_payloads_at_non_divisible_boundaries() {
        let four_bytes = r#"{"peer":"abc","room":"main","ct":"AQIDBA=="}"#;
        assert!(parser(4).parse_line(four_bytes).is_ok());

        let five_bytes = r#"{"peer":"abc","room":"main","ct":"AQIDBAU="}"#;
        assert!(parser(5).parse_line(five_bytes).is_ok());
        assert!(matches!(
            parser(4).parse_line(five_bytes),
            Err(ParseError::TooLarge(5, 4))
        ));
    }

    #[test]
    fn accepts_exact_limit_and_rejects_next_byte() {
        let max = DEFAULT_MAX_CT_MIB * 1024 * 1024;
        let encoded_len = max.div_ceil(3) * 4;

        let exact_ct = format!("{}==", "A".repeat(encoded_len - 2));
        let exact = format!(r#"{{"peer":"abc","room":"main","ct":"{exact_ct}"}}"#);
        assert!(parser(max).parse_line(&exact).is_ok());

        let over_ct = format!("{}=", "A".repeat(encoded_len - 1));
        let over = format!(r#"{{"peer":"abc","room":"main","ct":"{over_ct}"}}"#);
        assert!(matches!(
            parser(max).parse_line(&over),
            Err(ParseError::TooLarge(estimated, limit))
                if estimated == max + 1 && limit == max
        ));
    }

    #[test]
    fn rejects_too_large_payload() {
        let big = "A".repeat(12 * 1024 * 1024);
        let line = format!(r#"{{"peer":"abc","room":"main","ct":"{}"}}"#, big);
        assert!(matches!(
            parser(DEFAULT_MAX_CT_MIB * 1024 * 1024).parse_line(&line),
            Err(ParseError::TooLarge(..))
        ));
    }

    #[test]
    fn accepts_two_mb_payload_under_default_limit() {
        let img = "A".repeat(3 * 1024 * 1024);
        let line = format!(r#"{{"peer":"abc","room":"main","ct":"{}"}}"#, img);
        let env = parser(DEFAULT_MAX_CT_MIB * 1024 * 1024)
            .parse_line(&line)
            .expect("≈2 MB payload must pass under 4 MiB default");
        assert_eq!(env.peer, "abc");
    }

    #[test]
    fn explicit_parser_limit_overrides_default_limit() {
        let payload = "A".repeat(3 * 1024 * 1024);
        let line = format!(r#"{{"peer":"abc","room":"main","ct":"{}"}}"#, payload);

        assert!(matches!(
            parser(1024 * 1024).parse_line(&line),
            Err(ParseError::TooLarge(..))
        ));
        assert!(parser(4 * 1024 * 1024).parse_line(&line).is_ok());
    }

    #[test]
    fn derives_raw_websocket_limit_from_the_decoded_limit() {
        assert_eq!(parser(4 * 1024 * 1024).max_ws_message_bytes(), 5_657_944);
    }

    #[test]
    fn rejects_invalid_json() {
        assert!(matches!(
            parser(4).parse_line("not json at all"),
            Err(ParseError::InvalidJson(_))
        ));
    }
}
