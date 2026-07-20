mod common;
use common::{connect_and_auth, start_relay};

use futures_util::{SinkExt, StreamExt};
use serde_json::json;
use tokio::io::AsyncWriteExt;
use tokio_tungstenite::tungstenite::Message;

fn masked_frame(fin: bool, opcode: u8, payload: &[u8]) -> Vec<u8> {
    assert!(payload.len() <= u16::MAX as usize);
    let mask = [0x12, 0x34, 0x56, 0x78];
    let mut frame = vec![(u8::from(fin) << 7) | opcode];
    match payload.len() {
        len @ 0..=125 => frame.push(0x80 | len as u8),
        len => {
            frame.push(0x80 | 126);
            frame.extend_from_slice(&(len as u16).to_be_bytes());
        }
    }
    frame.extend_from_slice(&mask);
    frame.extend(
        payload
            .iter()
            .enumerate()
            .map(|(index, byte)| byte ^ mask[index % mask.len()]),
    );
    frame
}

fn masked_frame_header(fin: bool, opcode: u8, payload_len: usize) -> Vec<u8> {
    assert!(payload_len <= 125);
    vec![
        (u8::from(fin) << 7) | opcode,
        0x80 | payload_len as u8,
        0x12,
        0x34,
        0x56,
        0x78,
    ]
}

/// Peer A sends an OuterEnvelope addressed to peer B.
/// B receives a rewritten envelope where outer.peer = A (the sender),
/// not B (the original dest) — per protocol.md semantics.
#[tokio::test]
async fn two_peers_route_message() {
    let port = start_relay().await;
    let (mut ws_a, peer_a) = connect_and_auth(port).await;
    let (mut ws_b, peer_b) = connect_and_auth(port).await;

    // Base64 for {"session_id":"opaque-session","text":"hello"}; the relay must
    // carry it as opaque ciphertext and must not parse, log, compare, or route by it.
    let ct = "eyJzZXNzaW9uX2lkIjoib3BhcXVlLXNlc3Npb24iLCJ0ZXh0IjoiaGVsbG8ifQ==";
    // A sends: peer = dest (peer_b)
    ws_a.send(Message::text(
        json!({"peer": peer_b, "room": "main", "ct": ct}).to_string(),
    ))
    .await
    .unwrap();

    let received = tokio::time::timeout(tokio::time::Duration::from_secs(1), ws_b.next())
        .await
        .expect("timed out waiting for forwarded message")
        .unwrap()
        .unwrap();

    // B receives: peer = sender (peer_a), ct unchanged
    let received_json: serde_json::Value =
        serde_json::from_str(received.to_text().unwrap()).unwrap();
    assert_eq!(
        received_json["peer"], peer_a,
        "relay must rewrite peer to sender id"
    );
    assert_eq!(
        received_json["room"], "main",
        "relay must rewrite room to sender room"
    );
    assert_eq!(received_json["ct"], ct, "ct must be forwarded unchanged");
}

/// Sending to an unknown peer ID is silently dropped; the sender's connection stays alive.
#[tokio::test]
async fn dest_offline_drops_silently() {
    let port = start_relay().await;
    let (mut ws_a, _) = connect_and_auth(port).await;

    let envelope =
        json!({"peer": "bm9uZXhpc3RlbnRwZWVy", "room": "main", "ct": "aGVsbG8="}).to_string();
    ws_a.send(Message::text(envelope)).await.unwrap();

    // If the relay silently drops it, no message arrives and no close frame is sent.
    let result = tokio::time::timeout(tokio::time::Duration::from_millis(200), ws_a.next()).await;

    assert!(
        result.is_err(),
        "expected no message (connection alive), got {:?}",
        result
    );
}

/// A client that sends an invalid signature must have its WS closed within 100 ms.
#[tokio::test]
async fn invalid_sig_closes_ws() {
    let port = start_relay().await;
    let url = format!("ws://127.0.0.1:{port}");
    let (mut ws, _) = tokio_tungstenite::connect_async(&url).await.unwrap();

    use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
    use ed25519_dalek::SigningKey;
    let sk = SigningKey::generate(&mut rand::thread_rng());
    let vk = sk.verifying_key();

    // send hello
    ws.send(Message::text(
        json!({"type": "hello", "pubkey": B64.encode(vk.to_bytes()), "device_id": "test-device"})
            .to_string(),
    ))
    .await
    .unwrap();

    // receive and ignore challenge (we won't sign correctly)
    let challenge_msg = ws.next().await.unwrap().unwrap();
    let v: serde_json::Value = serde_json::from_str(challenge_msg.to_text().unwrap()).unwrap();
    assert_eq!(v["type"], "challenge");

    // send all-zero signature (invalid)
    ws.send(Message::text(
        json!({"type": "auth", "sig": B64.encode([0u8; 64])}).to_string(),
    ))
    .await
    .unwrap();

    // relay must close within 100 ms
    let close_result =
        tokio::time::timeout(tokio::time::Duration::from_millis(100), ws.next()).await;

    assert!(
        close_result.is_ok(),
        "relay did not close the connection within 100 ms"
    );
    match close_result.unwrap() {
        None | Some(Ok(Message::Close(_))) | Some(Err(_)) => {} // all acceptable
        Some(Ok(other)) => panic!("unexpected message after bad auth: {other:?}"),
    }
}

/// Fragmented unauthenticated input is rejected as soon as its declared payload
/// crosses the transport ceiling, before the final fragment payload is sent.
#[tokio::test]
async fn fragmented_oversized_hello_is_rejected_from_header_before_final_payload() {
    let port = start_relay().await;
    let url = format!("ws://127.0.0.1:{port}");
    let (mut ws, _) = tokio_tungstenite::connect_async(&url).await.unwrap();
    let ceiling = relay::resource_limits::PRE_AUTH_MESSAGE_MAX_BYTES;
    assert_eq!(ceiling % 2, 0, "test requires an even transport ceiling");

    let half = vec![b'x'; ceiling / 2];
    let stream = ws.get_mut();
    stream
        .write_all(&masked_frame(false, 0x1, &half))
        .await
        .unwrap();
    stream
        .write_all(&masked_frame(false, 0x0, &half))
        .await
        .unwrap();
    // Declare one byte beyond the ceiling, but deliberately withhold that byte.
    // A parser-level check cannot run because Tungstenite has no complete message.
    stream
        .write_all(&masked_frame_header(true, 0x0, 1))
        .await
        .unwrap();

    let close_result =
        tokio::time::timeout(tokio::time::Duration::from_millis(250), ws.next()).await;
    assert!(
        close_result.is_ok(),
        "relay waited for the oversized fragment payload instead of rejecting its header"
    );
    match close_result.unwrap() {
        None | Some(Ok(Message::Close(_))) | Some(Err(_)) => {}
        Some(Ok(other)) => panic!("unexpected message after oversized fragmented hello: {other:?}"),
    }
}

/// Oversized unauthenticated text is rejected before JSON parsing or registration.
#[tokio::test]
async fn oversized_hello_closes_ws() {
    let port = start_relay().await;
    let url = format!("ws://127.0.0.1:{port}");
    let (mut ws, _) = tokio_tungstenite::connect_async(&url).await.unwrap();

    ws.send(Message::text(
        "x".repeat(relay::protocol::outer::MAX_PRE_AUTH_FRAME_BYTES + 1),
    ))
    .await
    .unwrap();

    let close_result =
        tokio::time::timeout(tokio::time::Duration::from_millis(100), ws.next()).await;
    assert!(close_result.is_ok(), "relay did not reject oversized hello");
    match close_result.unwrap() {
        None | Some(Ok(Message::Close(_))) | Some(Err(_)) => {}
        Some(Ok(other)) => panic!("unexpected message after oversized hello: {other:?}"),
    }
}
