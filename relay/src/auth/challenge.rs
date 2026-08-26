pub use crate::protocol::generated::control::RELAY_AUTH_DOMAIN_PREFIX;
use crate::protocol::generated::control::{ClientAuthMsg, ServerAuthMsg};
use crate::rooms::RoomMeta;
use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
use ed25519_dalek::{Signature, VerifyingKey};
use rand::RngCore as _;

use crate::protocol::generated::limits::{
    RELAY_MAX_CWD_BYTES, RELAY_MAX_DEVICE_ID_BYTES, RELAY_MAX_MODEL_BYTES,
    RELAY_MAX_PRE_AUTH_FRAME_BYTES, RELAY_MAX_ROOM_ID_BYTES, RELAY_MAX_ROOM_NAME_BYTES,
    RELAY_MAX_SESSION_ID_BYTES, RELAY_MAX_THINKING_BYTES,
};

/// Authentication identity and initial room metadata accepted during the handshake.
#[derive(Debug)]
pub struct AuthenticatedPeer {
    pub verifying_key: VerifyingKey,
    pub peer_id: String,
    pub device_id: String,
    pub room_meta: RoomMeta,
}

/// Describes a malformed or invalid relay authentication handshake.
#[derive(Debug, thiserror::Error)]
pub enum AuthError {
    #[error("pre-auth frame too large: {actual} bytes (max {max})")]
    FrameTooLarge { actual: usize, max: usize },
    #[error("pre-auth field {field} too large: {actual} bytes (max {max})")]
    FieldTooLarge {
        field: &'static str,
        actual: usize,
        max: usize,
    },
    #[error("expected hello, got other message")]
    NoHello,
    #[error("invalid pubkey: {0}")]
    InvalidPubkey(String),
    #[error("empty device_id")]
    InvalidDeviceId,
    #[error("base64 decode error: {0}")]
    Base64(#[from] base64::DecodeError),
    #[error("invalid signature")]
    InvalidSig,
    #[error("unexpected message type in auth step")]
    UnexpectedMsg,
    #[error("json parse error: {0}")]
    Json(#[from] serde_json::Error),
}

/// Generates a fresh 32-byte random nonce. Returns (raw bytes, base64 string).
pub fn gen_nonce() -> ([u8; 32], String) {
    let mut nonce = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut nonce);
    let b64 = B64.encode(nonce);
    (nonce, b64)
}

/// Parse the initial `hello` frame into an authenticated peer bootstrap record.
///
/// # Errors
///
/// Returns [`AuthError::Json`] for malformed frames, [`AuthError::NoHello`]
/// for another message type, [`AuthError::InvalidDeviceId`] for an empty device
/// id, and the relevant key or base64 error when the advertised public key is
/// invalid.
pub fn parse_hello_bootstrap(line: &str, now_ms: i64) -> Result<AuthenticatedPeer, AuthError> {
    ensure_frame_size(line)?;
    let msg: ClientAuthMsg = serde_json::from_str(line)?;
    match msg {
        ClientAuthMsg::Hello {
            pubkey,
            device_id,
            room_id,
            room_meta,
        } => {
            if device_id.is_empty() {
                return Err(AuthError::InvalidDeviceId);
            }
            ensure_field_size("device_id", &device_id, RELAY_MAX_DEVICE_ID_BYTES)?;
            ensure_field_size("room_id", &room_id, RELAY_MAX_ROOM_ID_BYTES)?;
            if let Some(meta) = &room_meta {
                ensure_optional_field_size(
                    "room_meta.name",
                    &meta.name,
                    RELAY_MAX_ROOM_NAME_BYTES,
                )?;
                ensure_optional_field_size("room_meta.cwd", &meta.cwd, RELAY_MAX_CWD_BYTES)?;
                ensure_optional_field_size(
                    "room_meta.session_id",
                    &meta.session_id,
                    RELAY_MAX_SESSION_ID_BYTES,
                )?;
                ensure_optional_field_size("room_meta.model", &meta.model, RELAY_MAX_MODEL_BYTES)?;
                ensure_optional_field_size(
                    "room_meta.thinking",
                    &meta.thinking,
                    RELAY_MAX_THINKING_BYTES,
                )?;
            }
            let bytes = B64.decode(&pubkey)?;
            let arr: [u8; 32] = bytes
                .try_into()
                .map_err(|_| AuthError::InvalidPubkey("expected 32 bytes".into()))?;
            let verifying_key = VerifyingKey::from_bytes(&arr)
                .map_err(|e| AuthError::InvalidPubkey(e.to_string()))?;
            let peer_id = B64.encode(verifying_key.to_bytes());
            let meta = room_meta.unwrap_or_default();
            Ok(AuthenticatedPeer {
                verifying_key,
                peer_id,
                device_id,
                room_meta: RoomMeta {
                    room_id,
                    name: meta.name,
                    cwd: meta.cwd,
                    session_id: meta.session_id,
                    model: meta.model,
                    thinking: meta.thinking,
                    working: meta.working,
                    started_at: now_ms,
                },
            })
        }
        _ => Err(AuthError::NoHello),
    }
}

/// Serialises the challenge message to a JSONL string (no trailing newline).
pub fn challenge_line(nonce_b64: &str) -> String {
    serde_json::to_string(&ServerAuthMsg::Challenge {
        nonce: nonce_b64.to_owned(),
    })
    .expect("ServerAuthMsg serialisation is infallible")
}

/// Build the exact bytes covered by a relay-auth signature.
///
/// The generated schema constant supplies the domain prefix; the nonce is
/// appended unchanged so every peer signs `prefix ++ nonce`.
pub(crate) fn relay_auth_signing_bytes(nonce: &[u8]) -> Vec<u8> {
    let mut signed = Vec::with_capacity(RELAY_AUTH_DOMAIN_PREFIX.len() + nonce.len());
    signed.extend_from_slice(RELAY_AUTH_DOMAIN_PREFIX);
    signed.extend_from_slice(nonce);
    signed
}

/// Verify an `auth` frame's domain-separated signature against the challenge nonce.
///
/// # Errors
///
/// Returns [`AuthError::Json`] or [`AuthError::UnexpectedMsg`] for an invalid
/// auth frame, [`AuthError::Base64`] or [`AuthError::InvalidSig`] for an
/// invalid signature encoding, and [`AuthError::InvalidSig`] when verification
/// fails.
pub fn verify_auth(nonce: &[u8; 32], vk: &VerifyingKey, line: &str) -> Result<(), AuthError> {
    ensure_frame_size(line)?;
    let msg: ClientAuthMsg = serde_json::from_str(line)?;
    let sig_b64 = match msg {
        ClientAuthMsg::Auth { sig } => sig,
        _ => return Err(AuthError::UnexpectedMsg),
    };
    let sig_bytes = B64.decode(&sig_b64)?;
    let sig_arr: [u8; 64] = sig_bytes.try_into().map_err(|_| AuthError::InvalidSig)?;
    let sig = Signature::from_bytes(&sig_arr);
    use ed25519_dalek::Verifier as _;
    vk.verify(&relay_auth_signing_bytes(nonce), &sig)
        .map_err(|_| AuthError::InvalidSig)
}

fn ensure_frame_size(line: &str) -> Result<(), AuthError> {
    if line.len() > RELAY_MAX_PRE_AUTH_FRAME_BYTES {
        return Err(AuthError::FrameTooLarge {
            actual: line.len(),
            max: RELAY_MAX_PRE_AUTH_FRAME_BYTES,
        });
    }
    Ok(())
}

fn ensure_field_size(field: &'static str, value: &str, max: usize) -> Result<(), AuthError> {
    if value.len() > max {
        return Err(AuthError::FieldTooLarge {
            field,
            actual: value.len(),
            max,
        });
    }
    Ok(())
}

fn ensure_optional_field_size(
    field: &'static str,
    value: &Option<String>,
    max: usize,
) -> Result<(), AuthError> {
    if let Some(value) = value {
        ensure_field_size(field, value, max)?;
    }
    Ok(())
}
