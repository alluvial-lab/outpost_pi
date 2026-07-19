use std::net::SocketAddr;
use std::time::{SystemTime, UNIX_EPOCH};

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{ConnectInfo, State};
use axum::response::Response;
use futures_util::{SinkExt, StreamExt};
use tokio::sync::mpsc;
use tokio::time;
use tracing::{info, warn};

use crate::AppState;
use crate::auth::challenge::{challenge_line, gen_nonce, parse_hello_bootstrap, verify_auth};
use crate::handlers::connection_actor::{ActorDispatch, ConnectionActor, ConnectionActorServices};
use crate::protocol::frame::{FrameDecodeError, decode_relay_frame};
use crate::protocol::outer::max_ws_message_bytes;
use crate::reachability::RELAY_WS_PING_INTERVAL;
use crate::resource_limits::HANDSHAKE_STEP_TIMEOUT;

pub use crate::resource_limits::{MAX_CONTROL_CHECK_PEER_COST_PER_WINDOW, MAX_CONTROL_FRAME_PEERS};
/// Axum route handler: validates the WebSocket upgrade and hands the upgraded
/// socket to `handle_peer`, which owns the connection for its lifetime.
pub async fn ws_handler(
    ws: WebSocketUpgrade,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    State(state): State<AppState>,
) -> Response {
    ws.max_frame_size(max_ws_message_bytes())
        .max_message_size(max_ws_message_bytes())
        .on_upgrade(move |socket| handle_peer(socket, addr, state))
}

/// Owns one peer's WebSocket connection: hello/challenge/auth → register →
/// routing loop (forwarding outer envelopes + handling presence/rooms control
/// frames + sending 25 s keepalive pings) → unregister on disconnect.
async fn handle_peer(socket: WebSocket, peer_addr: SocketAddr, state: AppState) {
    let peer_addr = peer_addr.to_string();
    let (mut sink, mut stream) = socket.split();

    // ── 1. Wait for hello (with timeout) ──────────────────────────────────
    let hello_text = match next_handshake_text(&mut stream).await {
        Some(text) => text,
        None => {
            warn!(addr = %peer_addr, phase = "hello", "handshake step failed, closing");
            return;
        }
    };

    let started_at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64;
    let authenticated = match parse_hello_bootstrap(&hello_text, started_at) {
        Ok(peer) => peer,
        Err(e) => {
            warn!(addr = %peer_addr, err = %e, "bad hello, closing");
            return;
        }
    };
    let vk = authenticated.verifying_key;

    // ── 2. Send challenge ─────────────────────────────────────────────────
    let (nonce, nonce_b64) = gen_nonce();
    if sink
        .send(Message::Text(challenge_line(&nonce_b64)))
        .await
        .is_err()
    {
        return;
    }

    // ── 3. Receive and verify auth ────────────────────────────────────────
    let auth_text = match next_handshake_text(&mut stream).await {
        Some(text) => text,
        None => {
            warn!(addr = %peer_addr, phase = "auth", "handshake step failed, closing");
            return;
        }
    };

    if let Err(e) = verify_auth(&nonce, &vk, &auth_text) {
        warn!(addr = %peer_addr, err = %e, "auth failed, closing");
        let _ = sink.send(Message::Close(None)).await;
        return;
    }

    let peer_id = authenticated.peer_id;
    let device_id = authenticated.device_id;
    let peer_short = peer_id[peer_id.len().saturating_sub(8)..].to_string();
    let room_meta = authenticated.room_meta;
    let room_id = room_meta.room_id.clone();

    let registry = state.registry.clone();
    let rooms = state.rooms.clone();

    let (tx, mut rx) = mpsc::unbounded_channel::<Message>();
    let registration = registry
        .register(peer_id.clone(), room_meta, device_id.clone(), tx)
        .await;
    if !registration.superseded_same_device_conn_ids.is_empty() {
        info!(
            peer = %peer_short,
            room = %room_id,
            closed = registration.superseded_same_device_conn_ids.len(),
            "duplicate auth from same device; closed prior conn(s)"
        );
    }
    info!(
        peer = %peer_short,
        room = %room_id,
        addr = %peer_addr,
        superseded_existing = registration.superseded_existing,
        "authenticated"
    );

    let mut actor = ConnectionActor::new(
        peer_id.clone(),
        peer_short.clone(),
        room_id.clone(),
        registration.conn_id,
        ConnectionActorServices {
            registry: registry.clone(),
            presence: state.presence.clone(),
            rooms: rooms.clone(),
            mesh: state.mesh.clone(),
            mesh_auth: state.mesh_auth.clone(),
            metrics: state.metrics.clone(),
        },
    );

    // ── 4. Routing loop ───────────────────────────────────────────────────
    // Send a WS Ping every 25 s so NAT/LB idle timers don't close the connection.
    // First tick fires after 25 s (not immediately).
    let mut heartbeat = time::interval_at(
        time::Instant::now() + RELAY_WS_PING_INTERVAL,
        RELAY_WS_PING_INTERVAL,
    );

    'routing: loop {
        tokio::select! {
            item = stream.next() => {
                match item {
                    None | Some(Err(_)) => break,
                    Some(Ok(msg)) => {
                        let text = match msg {
                            Message::Text(t) => t,
                            Message::Close(_) => break,
                            // Pong frames are keepalive responses; Ping frames are
                            // answered automatically by axum's WS. Drop both.
                            Message::Ping(_) | Message::Pong(_) => continue,
                            Message::Binary(_) => continue, // ignore binary
                        };

                        let frame = match decode_relay_frame(&text) {
                            Ok(frame) => frame,
                            Err(FrameDecodeError::UnknownType(frame_type)) => {
                                warn!(
                                    peer = %peer_short,
                                    frame_type = %frame_type,
                                    "unknown relay frame type, dropping"
                                );
                                continue;
                            }
                            Err(err) => {
                                warn!(peer = %peer_short, err = %err, "invalid relay frame, dropping");
                                continue;
                            }
                        };

                        match actor.dispatch(frame).await {
                            ActorDispatch::Continue => {}
                            ActorDispatch::Close => break,
                            ActorDispatch::Send(text) => {
                                if sink.send(Message::Text(text)).await.is_err() {
                                    break;
                                }
                            }
                            ActorDispatch::SendMany(messages) => {
                                for text in messages {
                                    if sink.send(Message::Text(text)).await.is_err() {
                                        break 'routing;
                                    }
                                }
                            }
                        }
                    }
                }
            }
            result = rx.recv() => {
                match result {
                    Some(msg) => {
                        if sink.send(msg).await.is_err() {
                            break;
                        }
                    }
                    None => break,
                }
            }
            _ = heartbeat.tick() => {
                if sink.send(Message::Ping(Vec::new())).await.is_err() {
                    break;
                }
            }
        }
    }

    // Only clear this peer's room/presence subscriptions when the peer has
    // NO remaining live connections. Subscriptions are peer-scoped (not
    // conn-scoped), so an unconditional `unsubscribe_all` on a same-device
    // reconnect would wipe the replacement connection's freshly-replayed
    // subscriptions. `peer_offlined` is true only on the N→0 transition
    // (mirrors the presence-transition guard in `remove`).
    let remove = registry
        .unregister(&peer_id, &room_id, registration.conn_id)
        .await;
    if remove.peer_offlined {
        rooms.unsubscribe_all(&peer_id).await;
    }
    info!(peer = %peer_short, room = %room_id, addr = %peer_addr, "disconnected");
}

async fn next_handshake_text<S, E>(stream: &mut S) -> Option<String>
where
    S: futures_util::Stream<Item = Result<Message, E>> + Unpin,
{
    match tokio::time::timeout(HANDSHAKE_STEP_TIMEOUT, stream.next()).await {
        Ok(Some(Ok(Message::Text(text)))) => Some(text),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures_util::stream;

    #[tokio::test(start_paused = true)]
    async fn handshake_text_times_out_for_stalled_step() {
        let mut stalled = stream::pending::<Result<Message, ()>>();
        let task = tokio::spawn(async move { next_handshake_text(&mut stalled).await });
        tokio::time::advance(HANDSHAKE_STEP_TIMEOUT).await;
        assert!(task.await.expect("handshake task must finish").is_none());
    }

    #[tokio::test]
    async fn handshake_text_rejects_non_text_frames() {
        let mut binary = stream::iter([Ok::<_, ()>(Message::Binary(vec![1, 2, 3]))]);
        assert!(next_handshake_text(&mut binary).await.is_none());
    }
}
