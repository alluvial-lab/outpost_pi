use std::io;
use std::net::SocketAddr;
use std::pin::Pin;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::task::{Context, Poll, ready};
use std::time::{SystemTime, UNIX_EPOCH};

use axum::body::Body;
use axum::extract::ws::{CloseFrame as AxumCloseFrame, Message as RegistryMessage};
use axum::extract::{ConnectInfo, Request, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use futures_util::{SinkExt, StreamExt};
use hyper_util::rt::TokioIo;
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
use tokio::sync::mpsc;
use tokio::time;
use tokio_tungstenite::WebSocketStream;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::tungstenite::handshake::server::create_response_with_body;
use tokio_tungstenite::tungstenite::protocol::frame::coding::CloseCode;
use tokio_tungstenite::tungstenite::protocol::{CloseFrame, Role, WebSocketConfig};
use tracing::{info, warn};

use crate::AppState;
use crate::auth::challenge::{challenge_line, gen_nonce, parse_hello_bootstrap, verify_auth};
use crate::handlers::connection_actor::{ActorDispatch, ConnectionActor, ConnectionActorServices};
use crate::protocol::frame::decode_relay_frame;
use crate::reachability::RELAY_WS_PING_INTERVAL;
use crate::resource_limits::{
    HANDSHAKE_STEP_TIMEOUT, OUTBOUND_QUEUE_CAPACITY, PRE_AUTH_MESSAGE_MAX_BYTES,
};

pub use crate::resource_limits::{MAX_CONTROL_CHECK_PEER_COST_PER_WINDOW, MAX_CONTROL_FRAME_PEERS};
type PeerWebSocket = WebSocketStream<PreAuthGuard<TokioIo<hyper::upgrade::Upgraded>>>;

/// Validate and upgrade a peer WebSocket with pre-authentication admission.
///
/// The raw transport guard rejects a fragmented message from its frame header
/// as soon as its cumulative payload crosses the pre-authentication ceiling.
/// After successful signature verification, the same socket retains the larger
/// authenticated data-plane frame and message limits.
pub async fn ws_handler(
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    State(state): State<AppState>,
    mut request: Request,
) -> Response {
    let response = match create_response_with_body(&request, Body::empty) {
        Ok(response) => response,
        Err(_) => return StatusCode::BAD_REQUEST.into_response(),
    };
    let on_upgrade = hyper::upgrade::on(&mut request);

    tokio::spawn(async move {
        let upgraded = match on_upgrade.await {
            Ok(upgraded) => upgraded,
            Err(err) => {
                warn!(addr = %addr, err = %err, "WebSocket upgrade failed");
                return;
            }
        };
        let authenticated = Arc::new(AtomicBool::new(false));
        let guarded = PreAuthGuard::new(TokioIo::new(upgraded), authenticated.clone());
        let mut config = WebSocketConfig::default();
        config.max_frame_size = Some(state.outer_parser.max_ws_message_bytes());
        config.max_message_size = Some(state.outer_parser.max_ws_message_bytes());
        let socket = WebSocketStream::from_raw_socket(guarded, Role::Server, Some(config)).await;
        handle_peer(socket, authenticated, addr, state).await;
    });

    response
}

/// Owns one peer's WebSocket connection: hello/challenge/auth → register →
/// routing loop (forwarding outer envelopes + handling presence/rooms control
/// frames + sending 25 s keepalive pings) → unregister on disconnect.
async fn handle_peer(
    socket: PeerWebSocket,
    authenticated_transport: Arc<AtomicBool>,
    peer_addr: SocketAddr,
    state: AppState,
) {
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
        .send(Message::text(challenge_line(&nonce_b64)))
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
    authenticated_transport.store(true, Ordering::Release);

    let peer_id = authenticated.peer_id;
    let device_id = authenticated.device_id;
    let peer_short = peer_id[peer_id.len().saturating_sub(8)..].to_string();
    let room_meta = authenticated.room_meta;
    let room_id = room_meta.room_id.clone();

    let registry = state.registry.clone();
    let rooms = state.rooms.clone();

    let (tx, mut rx) = mpsc::channel::<RegistryMessage>(OUTBOUND_QUEUE_CAPACITY);
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
    let mut heartbeat = relay_heartbeat();
    // Bound attacker-triggerable diagnostics per authenticated connection.
    // Rejected frame content is never logged; the byte count and category are
    // sufficient to diagnose a bad client without creating a log amplifier.
    let mut invalid_frame_logs_remaining = 4usize;

    'routing: loop {
        tokio::select! {
            _ = registration.disconnect.cancelled() => {
                // A bounded mailbox dropped an update. Disconnect so this
                // recipient rehydrates authoritative state on reconnect.
                break;
            }
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
                            Message::Frame(_) => continue, // raw frame; not handled at this layer
                        };

                        let frame = match decode_relay_frame(&state.outer_parser, &text) {
                            Ok(frame) => frame,
                            Err(err) => {
                                if invalid_frame_logs_remaining > 0 {
                                    invalid_frame_logs_remaining -= 1;
                                    warn!(
                                        peer = %peer_short,
                                        category = err.category(),
                                        frame_bytes = text.len(),
                                        "invalid relay frame, dropping"
                                    );
                                }
                                continue;
                            }
                        };

                        match actor.dispatch(frame).await {
                            ActorDispatch::Continue => {}
                            ActorDispatch::Close => break,
                            ActorDispatch::Send(text) => {
                                if sink.send(Message::text(text)).await.is_err() {
                                    break;
                                }
                            }
                            ActorDispatch::SendMany(messages) => {
                                for text in messages {
                                    if sink.send(Message::text(text)).await.is_err() {
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
                        if sink.send(registry_message_to_transport(msg)).await.is_err() {
                            break;
                        }
                    }
                    None => break,
                }
            }
            _ = heartbeat.tick() => {
                if sink.send(Message::Ping(Vec::new().into())).await.is_err() {
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

fn relay_heartbeat() -> time::Interval {
    time::interval_at(
        time::Instant::now() + RELAY_WS_PING_INTERVAL,
        RELAY_WS_PING_INTERVAL,
    )
}

fn registry_message_to_transport(message: RegistryMessage) -> Message {
    match message {
        RegistryMessage::Text(text) => Message::Text(text.into()),
        RegistryMessage::Binary(data) => Message::Binary(data.into()),
        RegistryMessage::Ping(data) => Message::Ping(data.into()),
        RegistryMessage::Pong(data) => Message::Pong(data.into()),
        RegistryMessage::Close(frame) => {
            Message::Close(frame.map(|AxumCloseFrame { code, reason }| CloseFrame {
                code: CloseCode::from(code),
                reason: reason.into_owned().into(),
            }))
        }
    }
}

struct PreAuthGuard<S> {
    inner: S,
    authenticated: Arc<AtomicBool>,
    admission: PreAuthFrameAdmission,
}

impl<S> PreAuthGuard<S> {
    fn new(inner: S, authenticated: Arc<AtomicBool>) -> Self {
        Self {
            inner,
            authenticated,
            admission: PreAuthFrameAdmission::default(),
        }
    }
}

impl<S: AsyncRead + Unpin> AsyncRead for PreAuthGuard<S> {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buffer: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        let filled_before = buffer.filled().len();
        ready!(Pin::new(&mut this.inner).poll_read(cx, buffer))?;
        if !this.authenticated.load(Ordering::Acquire) {
            this.admission.inspect(&buffer.filled()[filled_before..])?;
        }
        Poll::Ready(Ok(()))
    }
}

impl<S: AsyncWrite + Unpin> AsyncWrite for PreAuthGuard<S> {
    fn poll_write(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buffer: &[u8],
    ) -> Poll<io::Result<usize>> {
        Pin::new(&mut self.get_mut().inner).poll_write(cx, buffer)
    }

    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.get_mut().inner).poll_flush(cx)
    }

    fn poll_shutdown(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.get_mut().inner).poll_shutdown(cx)
    }
}

#[derive(Default)]
struct PreAuthFrameAdmission {
    header: [u8; 14],
    header_len: usize,
    payload_remaining: u64,
    message_bytes: u64,
    message_in_progress: bool,
    reset_message_after_payload: bool,
}

impl PreAuthFrameAdmission {
    fn inspect(&mut self, mut bytes: &[u8]) -> io::Result<()> {
        while !bytes.is_empty() {
            if self.payload_remaining > 0 {
                let consumed = bytes.len().min(self.payload_remaining as usize);
                self.payload_remaining -= consumed as u64;
                bytes = &bytes[consumed..];
                if self.payload_remaining == 0 {
                    self.finish_frame();
                }
                continue;
            }

            let target = self.header_target_len();
            let copied = bytes.len().min(target - self.header_len);
            self.header[self.header_len..self.header_len + copied]
                .copy_from_slice(&bytes[..copied]);
            self.header_len += copied;
            bytes = &bytes[copied..];

            if self.header_len < self.header_target_len() {
                continue;
            }

            self.begin_frame()?;
            self.header_len = 0;
            if self.payload_remaining == 0 {
                self.finish_frame();
            }
        }
        Ok(())
    }

    fn header_target_len(&self) -> usize {
        if self.header_len < 2 {
            return 2;
        }
        let extended_len = match self.header[1] & 0x7f {
            126 => 2,
            127 => 8,
            _ => 0,
        };
        let mask_len = if self.header[1] & 0x80 == 0 { 0 } else { 4 };
        2 + extended_len + mask_len
    }

    fn begin_frame(&mut self) -> io::Result<()> {
        let fin = self.header[0] & 0x80 != 0;
        let opcode = self.header[0] & 0x0f;
        let payload_len = match self.header[1] & 0x7f {
            len @ 0..=125 => u64::from(len),
            126 => u64::from(u16::from_be_bytes([self.header[2], self.header[3]])),
            127 => {
                let mut encoded = [0u8; 8];
                encoded.copy_from_slice(&self.header[2..10]);
                u64::from_be_bytes(encoded)
            }
            _ => unreachable!("7-bit payload marker"),
        };

        self.reset_message_after_payload = false;
        if matches!(opcode, 0x0..=0x2) {
            if opcode != 0x0 && !self.message_in_progress {
                self.message_bytes = 0;
            }
            self.message_bytes = self.message_bytes.checked_add(payload_len).ok_or_else(|| {
                io::Error::new(
                    io::ErrorKind::InvalidData,
                    "pre-auth WebSocket message too large",
                )
            })?;
            if self.message_bytes > PRE_AUTH_MESSAGE_MAX_BYTES as u64 {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "pre-auth WebSocket message too large",
                ));
            }
            self.message_in_progress = !fin;
            self.reset_message_after_payload = fin;
        }
        self.payload_remaining = payload_len;
        Ok(())
    }

    fn finish_frame(&mut self) {
        if self.reset_message_after_payload {
            self.message_bytes = 0;
            self.message_in_progress = false;
            self.reset_message_after_payload = false;
        }
    }
}

async fn next_handshake_text<S, E>(stream: &mut S) -> Option<String>
where
    S: futures_util::Stream<Item = Result<Message, E>> + Unpin,
{
    match tokio::time::timeout(HANDSHAKE_STEP_TIMEOUT, stream.next()).await {
        Ok(Some(Ok(Message::Text(text)))) => Some(text.to_string()),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures_util::stream;
    use std::time::Duration;

    #[tokio::test(start_paused = true)]
    async fn heartbeat_first_tick_waits_one_full_interval_then_repeats() {
        let mut heartbeat = relay_heartbeat();

        assert!(
            tokio::time::timeout(Duration::ZERO, heartbeat.tick())
                .await
                .is_err(),
            "heartbeat must not send a ping immediately on connection"
        );
        tokio::time::advance(RELAY_WS_PING_INTERVAL - Duration::from_secs(1)).await;
        assert!(
            tokio::time::timeout(Duration::ZERO, heartbeat.tick())
                .await
                .is_err(),
            "heartbeat must wait for the complete first interval"
        );

        tokio::time::advance(Duration::from_secs(1)).await;
        heartbeat.tick().await;
        tokio::time::advance(RELAY_WS_PING_INTERVAL).await;
        heartbeat.tick().await;
    }

    #[tokio::test(start_paused = true)]
    async fn handshake_text_times_out_for_stalled_step() {
        let mut stalled = stream::pending::<Result<Message, ()>>();
        let task = tokio::spawn(async move { next_handshake_text(&mut stalled).await });
        tokio::time::advance(HANDSHAKE_STEP_TIMEOUT).await;
        assert!(task.await.expect("handshake task must finish").is_none());
    }

    #[tokio::test]
    async fn handshake_text_rejects_non_text_frames() {
        let mut binary = stream::iter([Ok::<_, ()>(Message::Binary(vec![1, 2, 3].into()))]);
        assert!(next_handshake_text(&mut binary).await.is_none());
    }
}
