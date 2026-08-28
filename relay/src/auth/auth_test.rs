use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
use ed25519_dalek::{Signer as _, SigningKey};
use serde::Deserialize;

use super::challenge::{
    AuthError, RELAY_AUTH_DOMAIN_PREFIX, gen_nonce, parse_hello_bootstrap,
    relay_auth_signing_bytes, verify_auth,
};

#[derive(Deserialize)]
struct RelayAuthDomainVector {
    #[serde(rename = "authDomainPrefix")]
    auth_domain_prefix: String,
    #[serde(rename = "nonceBase64")]
    nonce_base64: String,
    #[serde(rename = "signingBytesBase64")]
    signing_bytes_base64: String,
}

#[test]
fn relay_auth_signs_the_shared_cross_component_byte_vector() {
    let vector: RelayAuthDomainVector = serde_json::from_str(include_str!(
        "../../../protocol/fixtures/relay/auth-domain-vector.json"
    ))
    .expect("auth-domain vector must be valid JSON");
    let nonce = B64
        .decode(vector.nonce_base64)
        .expect("auth-domain vector nonce must be base64");
    let expected_signing_bytes = B64
        .decode(vector.signing_bytes_base64)
        .expect("auth-domain vector signing bytes must be base64");

    assert_eq!(
        RELAY_AUTH_DOMAIN_PREFIX,
        vector.auth_domain_prefix.as_bytes()
    );
    assert_eq!(relay_auth_signing_bytes(&nonce), expected_signing_bytes);
}

/// First message is not "hello" → NoHello error.
#[test]
fn sem_hello() {
    // Send an "auth" message before any hello
    let line = r#"{"type":"auth","sig":"AAAA"}"#;
    let err = parse_hello_bootstrap(line, 0).unwrap_err();
    assert!(matches!(err, AuthError::NoHello));
}

#[test]
fn hello_bootstrap_defaults_and_room_meta() {
    let sk = SigningKey::generate(&mut rand::thread_rng());
    let pubkey = B64.encode(sk.verifying_key().to_bytes());
    let line = format!(
        r#"{{"type":"hello","pubkey":"{}","device_id":"dev-1","room_id":"work","room_meta":{{"name":"Desk","cwd":"/repo","session_id":"sess-1","model":"m","thinking":"high","working":true,"background":true}}}}"#,
        pubkey
    );

    let peer = parse_hello_bootstrap(&line, 1234).unwrap();
    assert_eq!(peer.peer_id, pubkey);
    assert_eq!(peer.device_id, "dev-1");
    assert_eq!(peer.room_meta.room_id, "work");
    assert_eq!(peer.room_meta.name.as_deref(), Some("Desk"));
    assert_eq!(peer.room_meta.cwd.as_deref(), Some("/repo"));
    assert_eq!(peer.room_meta.session_id.as_deref(), Some("sess-1"));
    assert_eq!(peer.room_meta.model.as_deref(), Some("m"));
    assert_eq!(peer.room_meta.thinking.as_deref(), Some("high"));
    assert!(peer.room_meta.working);
    assert_eq!(peer.room_meta.background, Some(true));
    assert_eq!(peer.room_meta.started_at, 1234);
}

#[test]
fn hello_bootstrap_defaults_main_and_not_working() {
    let sk = SigningKey::generate(&mut rand::thread_rng());
    let pubkey = B64.encode(sk.verifying_key().to_bytes());
    let line = format!(
        r#"{{"type":"hello","pubkey":"{}","device_id":"dev-1"}}"#,
        pubkey
    );

    let peer = parse_hello_bootstrap(&line, 77).unwrap();
    assert_eq!(peer.device_id, "dev-1");
    assert_eq!(peer.room_meta.room_id, "main");
    assert!(!peer.room_meta.working);
    assert_eq!(peer.room_meta.background, Some(false));
    assert_eq!(peer.room_meta.started_at, 77);
}

/// Hello with an empty `device_id` is rejected at the auth boundary — two
/// malformed clients with empty ids would otherwise be treated as the same
/// device and close each other on duplicate auth.
#[test]
fn hello_with_empty_device_id_is_rejected() {
    let sk = SigningKey::generate(&mut rand::thread_rng());
    let pubkey = B64.encode(sk.verifying_key().to_bytes());
    let line = format!(
        r#"{{"type":"hello","pubkey":"{}","device_id":"","room_id":"main"}}"#,
        pubkey
    );

    let err = parse_hello_bootstrap(&line, 0).unwrap_err();
    assert!(matches!(err, AuthError::InvalidDeviceId), "got {err:?}");
}

/// Hello missing `device_id` entirely is rejected by serde (required field).
#[test]
fn hello_missing_device_id_is_rejected() {
    let sk = SigningKey::generate(&mut rand::thread_rng());
    let pubkey = B64.encode(sk.verifying_key().to_bytes());
    let line = format!(
        r#"{{"type":"hello","pubkey":"{}","room_id":"main"}}"#,
        pubkey
    );

    let err = parse_hello_bootstrap(&line, 0).unwrap_err();
    // serde rejects a missing required field as a Json error.
    assert!(matches!(err, AuthError::Json(_)), "got {err:?}");
}

#[test]
fn oversized_invalid_hello_rejects_before_json_parse() {
    let line = "x".repeat(crate::protocol::outer::MAX_PRE_AUTH_FRAME_BYTES + 1);
    let err = parse_hello_bootstrap(&line, 0).unwrap_err();
    assert!(matches!(err, AuthError::FrameTooLarge { .. }));
}

#[test]
fn oversized_hello_metadata_is_rejected() {
    let sk = SigningKey::generate(&mut rand::thread_rng());
    let pubkey = B64.encode(sk.verifying_key().to_bytes());
    let line = serde_json::json!({
        "type": "hello",
        "pubkey": pubkey,
        "device_id": "d".repeat(129),
        "room_id": "main",
    })
    .to_string();

    let err = parse_hello_bootstrap(&line, 0).unwrap_err();
    assert!(matches!(
        err,
        AuthError::FieldTooLarge {
            field: "device_id",
            actual: 129,
            max: 128,
        }
    ));
}

#[test]
fn metadata_limits_count_utf8_bytes() {
    let sk = SigningKey::generate(&mut rand::thread_rng());
    let pubkey = B64.encode(sk.verifying_key().to_bytes());
    let line = serde_json::json!({
        "type": "hello",
        "pubkey": pubkey,
        "device_id": "device",
        "room_id": "é".repeat(129),
    })
    .to_string();

    let err = parse_hello_bootstrap(&line, 0).unwrap_err();
    assert!(matches!(
        err,
        AuthError::FieldTooLarge {
            field: "room_id",
            actual: 258,
            max: 256,
        }
    ));
}

/// Valid key pair but signature covers wrong bytes → InvalidSig.
#[test]
fn sig_invalida() {
    let (nonce, _) = gen_nonce();
    let sk = SigningKey::generate(&mut rand::thread_rng());
    let vk = sk.verifying_key();

    // Sign something other than the domain-separated nonce
    let wrong_sig = sk.sign(b"not the nonce");
    let sig_b64 = B64.encode(wrong_sig.to_bytes());
    let line = format!(r#"{{"type":"auth","sig":"{}"}}"#, sig_b64);

    let err = verify_auth(&nonce, &vk, &line).unwrap_err();
    assert!(matches!(err, AuthError::InvalidSig));
}

/// Valid key pair, signature covers the correct nonce bytes → success.
#[test]
fn sig_valida() {
    let (nonce, _) = gen_nonce();
    let sk = SigningKey::generate(&mut rand::thread_rng());
    let vk = sk.verifying_key();

    // Sign the domain-separated nonce (prefix ++ nonce) — matches verify_auth.
    let mut signed = Vec::with_capacity(RELAY_AUTH_DOMAIN_PREFIX.len() + nonce.len());
    signed.extend_from_slice(RELAY_AUTH_DOMAIN_PREFIX);
    signed.extend_from_slice(&nonce);
    let sig = sk.sign(&signed);
    let sig_b64 = B64.encode(sig.to_bytes());
    let line = format!(r#"{{"type":"auth","sig":"{}"}}"#, sig_b64);

    verify_auth(&nonce, &vk, &line).unwrap();
}

/// The Outpost-Pi auth domain is a hard cutover: the legacy Remote Pi domain
/// is not accepted as a compatibility fallback.
#[test]
fn auth_domain_prefix_hard_cutover_rejects_legacy_signature() {
    let nonce = [7u8; 32];
    let sk = SigningKey::generate(&mut rand::thread_rng());
    let vk = sk.verifying_key();

    let mut legacy_signed = b"remote-pi-relay-auth-v1\n".to_vec();
    legacy_signed.extend_from_slice(&nonce);
    let legacy_sig = sk.sign(&legacy_signed);
    let legacy_line = format!(
        r#"{{"type":"auth","sig":"{}"}}"#,
        B64.encode(legacy_sig.to_bytes())
    );

    let err = verify_auth(&nonce, &vk, &legacy_line).unwrap_err();
    assert!(matches!(err, AuthError::InvalidSig));

    let mut current_signed = b"outpost-pi-relay-auth-v1\n".to_vec();
    current_signed.extend_from_slice(&nonce);
    let current_sig = sk.sign(&current_signed);
    let current_line = format!(
        r#"{{"type":"auth","sig":"{}"}}"#,
        B64.encode(current_sig.to_bytes())
    );

    verify_auth(&nonce, &vk, &current_line).unwrap();
}
