use std::collections::HashMap;
use std::sync::Arc;

use tracing::warn;

use crate::handlers::pi_forward::{
    MeshAuthCache, PiForwardResult, handle_malformed_pi_envelope, handle_pi_envelope,
};
use crate::mesh::MeshStore;
use crate::metrics::FirehoseMetrics;
use crate::peers::connections::ConnectionRegistry;
use crate::peers::registry::PeerRegistry;
use crate::peers::registry_event_publisher::RegistryEventPublisher;
use crate::peers::rooms::RoomStateStore;
use crate::presence::{PeerPresence, PresenceManager};
use crate::protocol::frame::{DecodedRelayFrame, PiEnvelopeFrame};
use crate::protocol::generated::control::RelayServerControlFrame;
use crate::protocol::outer::OuterEnvelope;
use crate::rooms::RoomManager;

use crate::resource_limits::{
    CONTROL_CHECK_PEER_COST_WINDOW, FixedWindowBudget, MAX_CONTROL_CHECK_PEER_COST_PER_WINDOW,
    MAX_CONTROL_FRAME_PEERS, MAX_PI_FORWARDS_PER_WINDOW, PI_FORWARD_WINDOW,
    ROOMS_DEDUP_CACHE_MAX_BYTES, ROOMS_DEDUP_CACHE_MAX_ENTRIES,
};

#[derive(Debug)]
struct CachedRoomsResponse {
    response: String,
    last_used: u64,
}

#[derive(Debug, Default)]
struct RoomsDedupCache {
    entries: HashMap<String, CachedRoomsResponse>,
    retained_bytes: usize,
    clock: u64,
}

impl RoomsDedupCache {
    fn is_unchanged(&mut self, peer_id: &str, response: &str) -> bool {
        let Some(entry) = self.entries.get_mut(peer_id) else {
            return false;
        };
        if entry.response != response {
            return false;
        }

        self.clock = self.clock.saturating_add(1);
        entry.last_used = self.clock;
        true
    }

    fn remember(&mut self, peer_id: String, response: String) {
        if let Some(previous) = self.entries.remove(&peer_id) {
            self.retained_bytes = self
                .retained_bytes
                .saturating_sub(peer_id.len() + previous.response.len());
        }

        let entry_bytes = peer_id.len().saturating_add(response.len());
        if entry_bytes > ROOMS_DEDUP_CACHE_MAX_BYTES {
            return;
        }

        while self.entries.len() >= ROOMS_DEDUP_CACHE_MAX_ENTRIES
            || self.retained_bytes.saturating_add(entry_bytes) > ROOMS_DEDUP_CACHE_MAX_BYTES
        {
            let Some(oldest_peer) = self
                .entries
                .iter()
                .min_by_key(|(_, entry)| entry.last_used)
                .map(|(peer, _)| peer.clone())
            else {
                break;
            };
            if let Some(evicted) = self.entries.remove(&oldest_peer) {
                self.retained_bytes = self
                    .retained_bytes
                    .saturating_sub(oldest_peer.len() + evicted.response.len());
            }
        }

        self.clock = self.clock.saturating_add(1);
        self.retained_bytes = self.retained_bytes.saturating_add(entry_bytes);
        self.entries.insert(
            peer_id,
            CachedRoomsResponse {
                response,
                last_used: self.clock,
            },
        );
    }

    #[cfg(test)]
    fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    #[cfg(test)]
    fn len(&self) -> usize {
        self.entries.len()
    }
}

#[derive(Debug)]
pub(crate) enum ActorDispatch {
    Continue,
    Close,
    Send(String),
    SendMany(Vec<String>),
}

#[derive(Debug)]
pub(crate) struct ControlCheckLimiter {
    budget: FixedWindowBudget,
}

impl ControlCheckLimiter {
    fn new() -> Self {
        Self {
            budget: FixedWindowBudget::new(
                CONTROL_CHECK_PEER_COST_WINDOW,
                MAX_CONTROL_CHECK_PEER_COST_PER_WINDOW,
            ),
        }
    }

    fn allow(&mut self, peer_cost: usize) -> bool {
        self.budget.allow(peer_cost)
    }
}

pub(crate) fn control_check_cost(peers: &[String]) -> usize {
    peers.len().max(1)
}

#[derive(Clone)]
pub(crate) struct ConnectionActorServices {
    pub(crate) registry: Arc<PeerRegistry>,
    pub(crate) presence: Arc<PresenceManager>,
    pub(crate) rooms: Arc<RoomManager>,
    pub(crate) mesh: Arc<MeshStore>,
    pub(crate) mesh_auth: Arc<MeshAuthCache>,
    pub(crate) metrics: Arc<FirehoseMetrics>,
}

pub(crate) struct ConnectionActor {
    pub(crate) peer_id: String,
    pub(crate) peer_short: String,
    pub(crate) room_id: String,
    conn_id: u64,
    pub(crate) delivery: Arc<ConnectionRegistry>,
    pub(crate) room_state: Arc<RoomStateStore>,
    pub(crate) events: Arc<RegistryEventPublisher>,
    pub(crate) presence: Arc<PresenceManager>,
    pub(crate) rooms: Arc<RoomManager>,
    mesh: Arc<MeshStore>,
    mesh_auth: Arc<MeshAuthCache>,
    metrics: Arc<FirehoseMetrics>,
    last_presence_resp: Option<String>,
    last_rooms_resp: RoomsDedupCache,
    control_check_limiter: ControlCheckLimiter,
    pi_forward_limiter: FixedWindowBudget,
}

impl ConnectionActor {
    pub(crate) fn new(
        peer_id: String,
        peer_short: String,
        room_id: String,
        conn_id: u64,
        services: ConnectionActorServices,
    ) -> Self {
        Self {
            peer_id,
            peer_short,
            room_id,
            conn_id,
            delivery: services.registry.connections(),
            room_state: services.registry.rooms(),
            events: services.registry.events(),
            presence: services.presence,
            rooms: services.rooms,
            mesh: services.mesh,
            mesh_auth: services.mesh_auth,
            metrics: services.metrics,
            last_presence_resp: None,
            last_rooms_resp: RoomsDedupCache::default(),
            control_check_limiter: ControlCheckLimiter::new(),
            pi_forward_limiter: FixedWindowBudget::new(
                PI_FORWARD_WINDOW,
                MAX_PI_FORWARDS_PER_WINDOW,
            ),
        }
    }

    pub(crate) async fn dispatch(&mut self, frame: DecodedRelayFrame) -> ActorDispatch {
        match frame {
            DecodedRelayFrame::Outer(frame) => self.dispatch_outer(frame).await,
            DecodedRelayFrame::Control(frame) => self.dispatch_control(frame).await,
            DecodedRelayFrame::PiEnvelope(frame) => self.dispatch_pi_envelope(frame).await,
            DecodedRelayFrame::MalformedPiEnvelope(frame) => {
                self.dispatch_malformed_pi_envelope(frame).await
            }
        }
    }

    async fn dispatch_outer(&mut self, env: OuterEnvelope) -> ActorDispatch {
        let ct_len = env.ct.len();
        let dest_peer = env.peer;
        let dest_room = env.room;
        let dest_tail = dest_peer[dest_peer.len().saturating_sub(8)..].to_string();

        // Rewrite: recipient sees sender's authenticated peer_id + sender's room_id.
        let rewritten = OuterEnvelope {
            peer: self.peer_id.clone(),
            room: self.room_id.clone(),
            ct: env.ct,
        };
        let fwd_line = rewritten.to_json_string();

        // Skip-sender: pass this connection's conn_id so multi-device Owners
        // don't echo their own outbound messages.
        if !self
            .delivery
            .send_to_room(
                &dest_peer,
                &dest_room,
                axum::extract::ws::Message::Text(fwd_line),
                self.conn_id,
            )
            .accepted()
        {
            warn!(
                from = %self.peer_short,
                dest = %dest_tail,
                room = %dest_room,
                bytes = ct_len,
                "dest (peer, room) not found, dropping",
            );
        }

        ActorDispatch::Continue
    }

    async fn dispatch_pi_envelope(&mut self, frame: PiEnvelopeFrame) -> ActorDispatch {
        if !self.allow_pi_forward() {
            return ActorDispatch::Close;
        }
        self.pi_forward_result_to_dispatch(
            handle_pi_envelope(
                &self.peer_id,
                self.conn_id,
                &self.room_id,
                frame,
                &self.delivery,
                &self.mesh,
                &self.mesh_auth,
            )
            .await,
        )
    }

    async fn dispatch_malformed_pi_envelope(&mut self, frame: serde_json::Value) -> ActorDispatch {
        self.pi_forward_result_to_dispatch(handle_malformed_pi_envelope(&frame, &self.room_id))
    }

    fn pi_forward_result_to_dispatch(&self, result: PiForwardResult) -> ActorDispatch {
        match result {
            PiForwardResult::Forwarded => ActorDispatch::Continue,
            PiForwardResult::TransportError(message) => match message {
                axum::extract::ws::Message::Text(text) => ActorDispatch::Send(text),
                _ => ActorDispatch::Continue,
            },
        }
    }

    fn allow_pi_forward(&mut self) -> bool {
        if self.pi_forward_limiter.allow(1) {
            return true;
        }

        warn!(
            peer = %self.peer_short,
            limit = MAX_PI_FORWARDS_PER_WINDOW,
            window_secs = PI_FORWARD_WINDOW.as_secs(),
            "pi_envelope rate limit exceeded, closing connection"
        );
        false
    }

    pub(crate) fn allow_control_check(&mut self, frame_type: &str, peers: &[String]) -> bool {
        let cost = control_check_cost(peers);
        if self.control_check_limiter.allow(cost) {
            return true;
        }

        warn!(
            peer = %self.peer_short,
            frame_type = %frame_type,
            cost,
            limit = MAX_CONTROL_CHECK_PEER_COST_PER_WINDOW,
            window_secs = CONTROL_CHECK_PEER_COST_WINDOW.as_secs(),
            max_peers_per_frame = MAX_CONTROL_FRAME_PEERS,
            "control frame check rate limit exceeded, dropping"
        );
        false
    }

    pub(crate) fn emit_deduped_presence(&mut self, states: Vec<PeerPresence>) -> ActorDispatch {
        let resp = serde_json::to_string(&RelayServerControlFrame::Presence { states })
            .expect("generated presence serialization is infallible");

        if self.last_presence_resp.as_deref() == Some(resp.as_str()) {
            self.metrics.inc_presence_suppressed(1);
            ActorDispatch::Continue
        } else {
            self.last_presence_resp = Some(resp.clone());
            self.metrics.inc_presence_emitted(1);
            ActorDispatch::Send(resp)
        }
    }

    pub(crate) fn emit_deduped_room_snapshots(&mut self, peers: Vec<String>) -> ActorDispatch {
        let mut messages = Vec::new();
        for target_peer in peers {
            let active_rooms = self.room_state.rooms_of(&target_peer);
            let resp = serde_json::to_string(&RelayServerControlFrame::Rooms {
                peer: target_peer.clone(),
                rooms: active_rooms,
            })
            .expect("generated rooms serialization is infallible");

            if self.last_rooms_resp.is_unchanged(&target_peer, &resp) {
                self.metrics.inc_rooms_suppressed(1);
                continue;
            }

            self.last_rooms_resp.remember(target_peer, resp.clone());
            self.metrics.inc_rooms_emitted(1);
            messages.push(resp);
        }

        if messages.is_empty() {
            ActorDispatch::Continue
        } else {
            ActorDispatch::SendMany(messages)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::extract::ws::Message;
    use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
    use ed25519_dalek::SigningKey;
    use tokio::sync::mpsc;

    use crate::metrics::FirehoseMetrics;
    use crate::peers::registry::PeerRegistry;
    use crate::presence::PresenceManager;
    use crate::protocol::frame::{FrameDecodeError, RelayControlFrame, decode_relay_frame};
    use crate::protocol::generated::control::{RELAY_CONTROL_FRAME_TYPES, RoomMetaUpdateFrame};
    use crate::protocol::outer::OuterEnvelopeParser;
    use crate::resource_limits::OUTBOUND_QUEUE_CAPACITY;
    use crate::rooms::{RoomManager, RoomMeta, RoomMetaPatch};

    fn actor_services() -> (Arc<PeerRegistry>, ConnectionActorServices) {
        let presence = Arc::new(PresenceManager::new());
        let rooms = Arc::new(RoomManager::new());
        let metrics = Arc::new(FirehoseMetrics::new());
        let registry = Arc::new(PeerRegistry::new(
            presence.clone(),
            rooms.clone(),
            metrics.clone(),
        ));
        let services = ConnectionActorServices {
            registry: registry.clone(),
            presence,
            rooms,
            mesh: Arc::new(MeshStore::open_in_memory().unwrap()),
            mesh_auth: Arc::new(MeshAuthCache::new()),
            metrics,
        };
        (registry, services)
    }

    fn make_meta(room_id: &str) -> RoomMeta {
        RoomMeta {
            room_id: room_id.to_string(),
            name: None,
            cwd: None,
            session_id: None,
            model: None,
            thinking: None,
            working: false,
            background: None,
            started_at: 0,
        }
    }

    fn text_from_rx(rx: &mut mpsc::Receiver<Message>) -> String {
        rx.try_recv()
            .expect("recipient must receive forwarded envelope")
            .to_text()
            .expect("forwarded envelope must be text")
            .to_string()
    }

    fn canonical_peer_id(seed: u8) -> String {
        let signing_key = SigningKey::from_bytes(&[seed; 32]);
        B64.encode(signing_key.verifying_key().to_bytes())
    }

    #[test]
    fn rooms_dedup_cache_does_not_retain_unbounded_unique_peers() {
        let mut actor = ConnectionActor::new(
            canonical_peer_id(255),
            "sender".to_string(),
            "main".to_string(),
            42,
            actor_services().1,
        );

        for seed in 0..=MAX_CONTROL_FRAME_PEERS as u8 {
            let _ = actor.emit_deduped_room_snapshots(vec![canonical_peer_id(seed)]);
        }

        assert!(
            actor.last_rooms_resp.len() <= ROOMS_DEDUP_CACHE_MAX_ENTRIES,
            "rooms dedup retained {} attacker-selected peers",
            actor.last_rooms_resp.len()
        );
    }

    #[test]
    fn rooms_dedup_cache_bounds_key_and_response_bytes() {
        let mut cache = RoomsDedupCache::default();
        for seed in 0..3 {
            cache.remember(
                canonical_peer_id(seed),
                "x".repeat(ROOMS_DEDUP_CACHE_MAX_BYTES / 2),
            );
        }

        assert!(cache.retained_bytes <= ROOMS_DEDUP_CACHE_MAX_BYTES);
        assert!(cache.len() < 3, "response bytes must force eviction");
    }

    #[tokio::test]
    async fn dispatch_malformed_pi_envelope_returns_bad_envelope_transport_error() {
        let (_, services) = actor_services();
        let mut actor = ConnectionActor::new(
            "sender-peer".to_string(),
            "der-peer".to_string(),
            "sender-room".to_string(),
            42,
            services,
        );

        let dispatch = actor
            .dispatch(DecodedRelayFrame::MalformedPiEnvelope(serde_json::json!({
                "type": "pi_envelope",
                "envelope": {
                    "from": "a:sess",
                    "to": "b:agent",
                    "id": "018f4444-4444-7444-8444-444444444444",
                    "re": null,
                    "body": { "type": "ping", "session_id": "opaque-session" }
                }
            })))
            .await;

        let ActorDispatch::Send(text) = dispatch else {
            panic!("malformed pi_envelope must send a transport_error");
        };
        let frame: serde_json::Value = serde_json::from_str(&text).unwrap();
        assert_eq!(frame["type"], "pi_envelope_in");
        assert_eq!(frame["from_pc"], "_relay");
        assert_eq!(frame["envelope"]["from"], "_relay");
        assert_eq!(frame["envelope"]["to"], "a:sess");
        assert_eq!(
            frame["envelope"]["re"],
            "018f4444-4444-7444-8444-444444444444"
        );
        assert_eq!(frame["envelope"]["body"]["type"], "transport_error");
        assert_eq!(frame["envelope"]["body"]["reason"], "bad_envelope");
    }

    #[test]
    fn constructs_with_per_connection_state_empty() {
        let actor = ConnectionActor::new(
            "peer-12345678".to_string(),
            "12345678".to_string(),
            "main".to_string(),
            42,
            actor_services().1,
        );

        assert_eq!(actor.peer_id, "peer-12345678");
        assert_eq!(actor.peer_short, "12345678");
        assert_eq!(actor.room_id, "main");
        assert_eq!(actor.conn_id, 42);
        assert!(actor.last_presence_resp.is_none());
        assert!(actor.last_rooms_resp.is_empty());
        assert_eq!(actor.control_check_limiter.budget.used(), 0);
        assert_eq!(actor.pi_forward_limiter.used(), 0);
    }

    #[test]
    fn generated_presence_snapshot_preserves_wire_value() {
        let mut actor = ConnectionActor::new(
            "app".to_string(),
            "app".to_string(),
            "main".to_string(),
            42,
            actor_services().1,
        );

        let ActorDispatch::Send(text) = actor.emit_deduped_presence(vec![PeerPresence {
            peer: "pi".to_string(),
            online: false,
            since_ts: Some(123),
        }]) else {
            panic!("first presence snapshot must be emitted");
        };

        assert_eq!(
            serde_json::from_str::<serde_json::Value>(&text).unwrap(),
            serde_json::json!({
                "type": "presence",
                "states": [{"peer": "pi", "online": false, "since_ts": 123}],
            })
        );
    }

    #[tokio::test]
    async fn generated_rooms_snapshot_preserves_wire_value() {
        let (registry, services) = actor_services();
        let (tx, _rx) = mpsc::channel::<Message>(OUTBOUND_QUEUE_CAPACITY);
        registry
            .register(
                "pi".to_string(),
                RoomMeta {
                    room_id: "main".to_string(),
                    name: Some("Main".to_string()),
                    cwd: None,
                    session_id: None,
                    model: Some("model-1".to_string()),
                    thinking: None,
                    working: true,
                    background: Some(true),
                    started_at: 123,
                },
                "dev-a".to_string(),
                tx,
            )
            .await;
        let mut actor = ConnectionActor::new(
            "app".to_string(),
            "app".to_string(),
            "main".to_string(),
            42,
            services,
        );

        let ActorDispatch::SendMany(messages) =
            actor.emit_deduped_room_snapshots(vec!["pi".to_string()])
        else {
            panic!("first rooms snapshot must be emitted");
        };

        assert_eq!(
            serde_json::from_str::<serde_json::Value>(&messages[0]).unwrap(),
            serde_json::json!({
                "type": "rooms",
                "peer": "pi",
                "rooms": [{
                    "room_id": "main",
                    "name": "Main",
                    "model": "model-1",
                    "working": true,
                    "background": true,
                    "started_at": 123,
                }],
            })
        );
    }

    #[test]
    fn control_check_limiter_counts_peer_cost_and_rejects_over_budget() {
        let mut limiter = ControlCheckLimiter::new();

        assert!(limiter.allow(MAX_CONTROL_CHECK_PEER_COST_PER_WINDOW));
        assert!(!limiter.allow(1));
    }

    #[test]
    fn control_check_cost_charges_empty_checks() {
        assert_eq!(control_check_cost(&[]), 1);
    }

    #[test]
    fn pi_forward_limiter_accepts_exact_budget_then_closes_connection() {
        let mut actor = ConnectionActor::new(
            "peer-12345678".to_string(),
            "12345678".to_string(),
            "main".to_string(),
            42,
            actor_services().1,
        );

        for _ in 0..MAX_PI_FORWARDS_PER_WINDOW {
            assert!(actor.allow_pi_forward());
        }
        assert!(!actor.allow_pi_forward());
    }

    #[test]
    fn generated_control_dispatch_coverage_tracks_all_variants() {
        let covered_variants = [
            RelayControlFrame::SubscribePresence { peers: Vec::new() },
            RelayControlFrame::UnsubscribePresence { peers: Vec::new() },
            RelayControlFrame::PresenceCheck { peers: Vec::new() },
            RelayControlFrame::SubscribeRooms { peers: Vec::new() },
            RelayControlFrame::UnsubscribeRooms { peers: Vec::new() },
            RelayControlFrame::RoomsCheck { peers: Vec::new() },
            RelayControlFrame::RoomMetaUpdate(RoomMetaUpdateFrame {
                room_id: None,
                meta: RoomMetaPatch::default(),
            }),
        ];

        assert_eq!(covered_variants.len(), RELAY_CONTROL_FRAME_TYPES.len());
        for frame in &covered_variants {
            assert!(RELAY_CONTROL_FRAME_TYPES.contains(&frame.wire_type()));
        }
    }

    #[test]
    fn malformed_control_peers_reject_at_decode_boundary() {
        let err = decode_relay_frame(
            &OuterEnvelopeParser::new(1024),
            r#"{"type":"subscribe_presence","peers":"pi"}"#,
        )
        .expect_err("malformed control frame must fail before dispatch");

        assert!(matches!(err, FrameDecodeError::InvalidJson(_)));
    }

    #[test]
    fn empty_control_peers_remain_valid_at_decode_boundary() {
        let frame = decode_relay_frame(
            &OuterEnvelopeParser::new(1024),
            r#"{"type":"presence_check","peers":[]}"#,
        )
        .expect("empty peer list is a valid typed control frame");

        assert!(matches!(
            frame,
            DecodedRelayFrame::Control(RelayControlFrame::PresenceCheck { peers })
                if peers.is_empty()
        ));
    }

    #[tokio::test]
    async fn dispatch_routes_control_frames_to_typed_handler() {
        let (_, services) = actor_services();
        let mut actor = ConnectionActor::new(
            "app".to_string(),
            "app".to_string(),
            "main".to_string(),
            42,
            services,
        );

        let dispatch = actor
            .dispatch(DecodedRelayFrame::Control(
                RelayControlFrame::PresenceCheck {
                    peers: vec![canonical_peer_id(1)],
                },
            ))
            .await;

        assert!(matches!(dispatch, ActorDispatch::Send(_)));
    }

    #[tokio::test]
    async fn dispatch_outer_forwards_ct_verbatim_and_rewrites_sender_identity() {
        let (registry, services) = actor_services();
        let (dest_tx, mut dest_rx) = mpsc::channel::<Message>(OUTBOUND_QUEUE_CAPACITY);
        let _dest_conn = registry
            .register(
                "dest-peer".to_string(),
                make_meta("dest-room"),
                "dev-a".to_string(),
                dest_tx,
            )
            .await;

        let mut actor = ConnectionActor::new(
            "sender-peer".to_string(),
            "der-peer".to_string(),
            "sender-room".to_string(),
            42,
            services,
        );
        let opaque_ct = "eyJ0eXBlIjoidXNlcl9tZXNzYWdlIiwidGV4dCI6ImRvIG5vdCBkZWNvZGUifQ==";

        let dispatch = actor
            .dispatch(DecodedRelayFrame::Outer(OuterEnvelope {
                peer: "dest-peer".to_string(),
                room: "dest-room".to_string(),
                ct: opaque_ct.to_string(),
            }))
            .await;

        assert!(matches!(dispatch, ActorDispatch::Continue));
        let delivered: OuterEnvelope = serde_json::from_str(&text_from_rx(&mut dest_rx)).unwrap();
        assert_eq!(delivered.peer, "sender-peer");
        assert_eq!(delivered.room, "sender-room");
        assert_eq!(delivered.ct, opaque_ct);
    }

    #[tokio::test]
    async fn dispatch_outer_targets_exact_destination_room_without_cross_room_contamination() {
        let (registry, services) = actor_services();
        let (target_tx, mut target_rx) = mpsc::channel::<Message>(OUTBOUND_QUEUE_CAPACITY);
        let (other_tx, mut other_rx) = mpsc::channel::<Message>(OUTBOUND_QUEUE_CAPACITY);
        let _target_conn = registry
            .register(
                "dest-peer".to_string(),
                make_meta("target-room"),
                "dev-a".to_string(),
                target_tx,
            )
            .await;
        let _other_conn = registry
            .register(
                "dest-peer".to_string(),
                make_meta("other-room"),
                "dev-a".to_string(),
                other_tx,
            )
            .await;

        let mut actor = ConnectionActor::new(
            "sender-peer".to_string(),
            "der-peer".to_string(),
            "sender-room".to_string(),
            42,
            services,
        );

        let dispatch = actor
            .dispatch(DecodedRelayFrame::Outer(OuterEnvelope {
                peer: "dest-peer".to_string(),
                room: "target-room".to_string(),
                ct: "opaque-bytes".to_string(),
            }))
            .await;

        assert!(matches!(dispatch, ActorDispatch::Continue));
        let delivered: OuterEnvelope = serde_json::from_str(&text_from_rx(&mut target_rx)).unwrap();
        assert_eq!(delivered.ct, "opaque-bytes");
        assert!(
            other_rx.try_recv().is_err(),
            "outer forwarding must not leak into sibling rooms for the same peer"
        );
    }

    #[tokio::test]
    async fn dispatch_outer_skips_sender_connection_without_suppressing_other_matching_connections()
    {
        let (registry, services) = actor_services();
        let (sender_tx, mut sender_rx) = mpsc::channel::<Message>(OUTBOUND_QUEUE_CAPACITY);
        let (other_tx, mut other_rx) = mpsc::channel::<Message>(OUTBOUND_QUEUE_CAPACITY);
        let sender_conn = registry
            .register(
                "owner-peer".to_string(),
                make_meta("main"),
                "dev-a".to_string(),
                sender_tx,
            )
            .await;
        let _other_conn = registry
            .register(
                "owner-peer".to_string(),
                make_meta("main"),
                "dev-b".to_string(),
                other_tx,
            )
            .await;

        let mut actor = ConnectionActor::new(
            "owner-peer".to_string(),
            "ner-peer".to_string(),
            "main".to_string(),
            sender_conn.conn_id,
            services,
        );

        let dispatch = actor
            .dispatch(DecodedRelayFrame::Outer(OuterEnvelope {
                peer: "owner-peer".to_string(),
                room: "main".to_string(),
                ct: "same-room-opaque".to_string(),
            }))
            .await;

        assert!(matches!(dispatch, ActorDispatch::Continue));
        assert!(
            sender_rx.try_recv().is_err(),
            "originating connection must not receive its own forwarded envelope"
        );
        let delivered: OuterEnvelope = serde_json::from_str(&text_from_rx(&mut other_rx)).unwrap();
        assert_eq!(delivered.peer, "owner-peer");
        assert_eq!(delivered.room, "main");
        assert_eq!(delivered.ct, "same-room-opaque");
    }
}
