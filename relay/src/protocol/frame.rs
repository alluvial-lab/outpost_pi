//! Inbound relay WebSocket frame decode boundary.
//!
//! This module is the single place that classifies authenticated inbound text
//! frames as relay control, cross-PC forwarding, or app↔Pi outer envelopes. It
//! consumes generated serde contracts. `serde_json::Value` is limited to the
//! boundary probe and the compatibility `bad_envelope` path for malformed
//! cross-PC frames, whose original envelope fields remain opaque relay data.

pub use crate::protocol::generated::control::RelayControlFrame;
pub use crate::protocol::generated::cross_pc::PiEnvelopeFrame;
use crate::protocol::generated::frame::{RELAY_INBOUND_FRAME_TYPES, RelayInboundFrame};
pub use crate::protocol::generated::outer::OuterEnvelope;
use crate::protocol::outer::{self, OuterEnvelopeParser};

/// Classifies one validated inbound relay frame for typed dispatch.
#[derive(Debug)]
pub enum DecodedRelayFrame {
    Outer(OuterEnvelope),
    Control(RelayControlFrame),
    PiEnvelope(PiEnvelopeFrame),
    /// Compatibility escape hatch for malformed `pi_envelope` frames: the
    /// boundary has classified the frame type, but the existing cross-PC
    /// transport-error path still needs the raw envelope fields to correlate a
    /// `bad_envelope` response.
    MalformedPiEnvelope(serde_json::Value),
}

/// Describes a frame rejected at the relay's inbound decoding boundary.
#[derive(Debug, thiserror::Error)]
pub enum FrameDecodeError {
    #[error("raw frame too large: {actual} bytes (max {max})")]
    RawTooLarge { actual: usize, max: usize },
    #[error("invalid json: {0}")]
    InvalidJson(#[from] serde_json::Error),
    #[error("unknown relay frame type ({type_bytes} bytes)")]
    UnknownType { type_bytes: usize },
    #[error("outer envelope too large: {estimated} bytes (max {max})")]
    OuterTooLarge { estimated: usize, max: usize },
}

impl FrameDecodeError {
    /// Return a content-free diagnostic category safe for relay logs.
    pub fn category(&self) -> &'static str {
        match self {
            Self::RawTooLarge { .. } => "raw_too_large",
            Self::InvalidJson(_) => "invalid_json",
            Self::UnknownType { .. } => "unknown_type",
            Self::OuterTooLarge { .. } => "outer_too_large",
        }
    }
}

/// Decode and classify an authenticated inbound text frame before dispatch.
///
/// # Errors
///
/// Returns [`FrameDecodeError::InvalidJson`] for malformed JSON,
/// [`FrameDecodeError::UnknownType`] for unsupported typed frames, or
/// [`FrameDecodeError::OuterTooLarge`] when an outer envelope exceeds its
/// configured ciphertext limit.
pub fn decode_relay_frame(
    parser: &OuterEnvelopeParser,
    text: &str,
) -> Result<DecodedRelayFrame, FrameDecodeError> {
    decode_relay_frame_with_limits(text, parser.max_ws_message_bytes(), parser)
}

/// Decode with injected raw and decoded-payload limits.
///
/// This testable boundary checks the UTF-8 text size before any JSON
/// allocation. Outer payloads remain opaque and are size-estimated from their
/// base64 representation rather than decoded by the relay.
pub(crate) fn decode_relay_frame_with_limits(
    text: &str,
    max_raw_bytes: usize,
    parser: &OuterEnvelopeParser,
) -> Result<DecodedRelayFrame, FrameDecodeError> {
    if text.len() > max_raw_bytes {
        return Err(FrameDecodeError::RawTooLarge {
            actual: text.len(),
            max: max_raw_bytes,
        });
    }

    let value: serde_json::Value = serde_json::from_str(text)?;
    let Some(frame_type) = value
        .get("type")
        .and_then(serde_json::Value::as_str)
        .map(str::to_owned)
    else {
        return Ok(DecodedRelayFrame::Outer(parser.parse_line(text)?));
    };

    if !RELAY_INBOUND_FRAME_TYPES.contains(&frame_type.as_str()) {
        return Err(FrameDecodeError::UnknownType {
            type_bytes: frame_type.len(),
        });
    }

    if frame_type == "pi_envelope" {
        return match serde_json::from_value::<RelayInboundFrame>(value.clone()) {
            Ok(RelayInboundFrame::PiEnvelope(frame)) => Ok(DecodedRelayFrame::PiEnvelope(frame)),
            Ok(RelayInboundFrame::Control(_)) => {
                unreachable!("pi_envelope cannot decode as control")
            }
            Err(_) => Ok(DecodedRelayFrame::MalformedPiEnvelope(value)),
        };
    }

    match serde_json::from_value::<RelayInboundFrame>(value)? {
        RelayInboundFrame::Control(frame) => Ok(DecodedRelayFrame::Control(frame)),
        RelayInboundFrame::PiEnvelope(_) => {
            unreachable!("control frame cannot decode as pi_envelope")
        }
    }
}

impl From<outer::ParseError> for FrameDecodeError {
    fn from(err: outer::ParseError) -> Self {
        match err {
            outer::ParseError::InvalidJson(err) => FrameDecodeError::InvalidJson(err),
            outer::ParseError::TooLarge(estimated, max) => {
                FrameDecodeError::OuterTooLarge { estimated, max }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn invalid_json_rejects_before_dispatch() {
        assert!(matches!(
            decode_relay_frame(&OuterEnvelopeParser::new(1024), "not json"),
            Err(FrameDecodeError::InvalidJson(_))
        ));
    }

    #[test]
    fn raw_limit_runs_before_json_parse() {
        let err = decode_relay_frame_with_limits("not json", 3, &OuterEnvelopeParser::new(1024))
            .expect_err("over-limit malformed input must fail on size first");
        assert!(matches!(
            err,
            FrameDecodeError::RawTooLarge { actual: 8, max: 3 }
        ));
    }

    #[test]
    fn injected_decoded_limit_accepts_boundary_and_rejects_next_quantum() {
        let accepted = r#"{"peer":"dest","room":"main","ct":"AAAA"}"#;
        assert!(
            decode_relay_frame_with_limits(accepted, 1024, &OuterEnvelopeParser::new(3)).is_ok()
        );

        let rejected = r#"{"peer":"dest","room":"main","ct":"AAAAAAAA"}"#;
        assert!(matches!(
            decode_relay_frame_with_limits(rejected, 1024, &OuterEnvelopeParser::new(3)),
            Err(FrameDecodeError::OuterTooLarge {
                estimated: 6,
                max: 3
            })
        ));
    }

    #[test]
    fn unknown_typed_frame_records_only_its_byte_count() {
        let err = decode_relay_frame(
            &OuterEnvelopeParser::new(1024),
            r#"{"type":"mystery_frame","peers":[]}"#,
        )
        .expect_err("unknown typed frame must fail at decode boundary");
        assert!(matches!(
            &err,
            FrameDecodeError::UnknownType { type_bytes: 13 }
        ));
        assert_eq!(err.to_string(), "unknown relay frame type (13 bytes)");
        assert_eq!(err.category(), "unknown_type");
    }

    #[test]
    fn no_type_outer_envelope_decodes() {
        let frame = decode_relay_frame(
            &OuterEnvelopeParser::new(1024),
            r#"{"peer":"dest","room":"main","ct":"QUJDRA=="}"#,
        )
        .expect("outer envelope without type must decode");
        assert!(matches!(
            frame,
            DecodedRelayFrame::Outer(OuterEnvelope { peer, room, ct })
                if peer == "dest" && room == "main" && ct == "QUJDRA=="
        ));
    }

    #[test]
    fn ct_too_large_rejects_at_boundary() {
        let big = "A".repeat(12 * 1024 * 1024);
        let line = format!(r#"{{"peer":"dest","room":"main","ct":"{}"}}"#, big);
        let err = decode_relay_frame_with_limits(
            &line,
            line.len() + 1,
            &OuterEnvelopeParser::new(outer::DEFAULT_MAX_CT_MIB * 1024 * 1024),
        )
        .expect_err("oversized ct must fail");
        assert!(matches!(
            err,
            FrameDecodeError::OuterTooLarge { estimated, max }
                if estimated > max && max == outer::DEFAULT_MAX_CT_MIB * 1024 * 1024
        ));
    }

    #[test]
    fn known_control_frame_decodes_to_generated_variant() {
        let frame = decode_relay_frame(
            &OuterEnvelopeParser::new(1024),
            r#"{"type":"subscribe_presence","peers":["pi-a"]}"#,
        )
        .expect("known control frame must decode");
        assert!(matches!(
            frame,
            DecodedRelayFrame::Control(RelayControlFrame::SubscribePresence { peers })
                if peers == vec!["pi-a".to_string()]
        ));
    }
}
