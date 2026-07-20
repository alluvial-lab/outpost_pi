use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
use ed25519_dalek::VerifyingKey;

/// Return whether a peer id is the canonical base64 encoding of an Ed25519 public key.
pub(crate) fn is_canonical_peer_id(peer_id: &str) -> bool {
    let Ok(bytes) = B64.decode(peer_id) else {
        return false;
    };
    let Ok(key_bytes) = <[u8; 32]>::try_from(bytes) else {
        return false;
    };

    VerifyingKey::from_bytes(&key_bytes).is_ok() && B64.encode(key_bytes) == peer_id
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::SigningKey;

    #[test]
    fn accepts_only_canonical_ed25519_peer_ids() {
        let signing_key = SigningKey::from_bytes(&[7; 32]);
        let canonical = B64.encode(signing_key.verifying_key().to_bytes());

        assert!(is_canonical_peer_id(&canonical));
        assert!(!is_canonical_peer_id("peer"));
        assert!(!is_canonical_peer_id(canonical.trim_end_matches('=')));
    }
}
