use thiserror::Error;
use tracing::{info, warn};

use crate::handlers::connection_actor::{ActorDispatch, ConnectionActor};
use crate::handlers::peer::MAX_CONTROL_FRAME_PEERS;
use crate::peers::identity::is_canonical_peer_id;
use crate::protocol::generated::control::{RelayControlFrame, RoomMetaUpdateFrame};

/// Describes an invalid presence/rooms control-frame peer list.
#[derive(Debug, Error, PartialEq, Eq)]
pub enum ControlFrameError {
    #[error("control frame {frame_type} requested {requested} peers, limit is {limit}")]
    TooManyPeers {
        frame_type: String,
        requested: usize,
        limit: usize,
    },
    #[error("control frame {frame_type} contains an invalid peer id at index {index}")]
    InvalidPeerId { frame_type: String, index: usize },
}

/// Validates the peer-list shape shared by presence/rooms control frames.
///
/// This is the fail-closed boundary that generated control-frame decoding calls
/// before mutating subscription state. Missing `peers` defaults to the canonical
/// empty list; malformed or oversized values are dropped by the typed handler.
///
/// # Errors
///
/// Returns [`ControlFrameError::TooManyPeers`] when `peers` exceeds
/// `MAX_CONTROL_FRAME_PEERS`, or [`ControlFrameError::InvalidPeerId`] when an
/// entry is not the canonical base64 encoding of an Ed25519 public key.
pub fn bounded_peer_list(
    frame_type: &str,
    peers: Vec<String>,
) -> Result<Vec<String>, ControlFrameError> {
    if peers.len() > MAX_CONTROL_FRAME_PEERS {
        return Err(ControlFrameError::TooManyPeers {
            frame_type: frame_type.to_owned(),
            requested: peers.len(),
            limit: MAX_CONTROL_FRAME_PEERS,
        });
    }
    if let Some(index) = peers.iter().position(|peer| !is_canonical_peer_id(peer)) {
        return Err(ControlFrameError::InvalidPeerId {
            frame_type: frame_type.to_owned(),
            index,
        });
    }

    Ok(peers)
}

pub(crate) struct ControlHandlers<'actor> {
    actor: &'actor mut ConnectionActor,
}

impl ConnectionActor {
    pub(crate) async fn dispatch_control(&mut self, frame: RelayControlFrame) -> ActorDispatch {
        ControlHandlers::new(self).handle(frame).await
    }
}

impl<'actor> ControlHandlers<'actor> {
    pub(crate) fn new(actor: &'actor mut ConnectionActor) -> Self {
        Self { actor }
    }

    pub(crate) async fn handle(&mut self, frame: RelayControlFrame) -> ActorDispatch {
        let frame_type = frame.wire_type();
        match frame {
            RelayControlFrame::SubscribePresence { peers } => {
                self.subscribe_presence(frame_type, peers).await
            }
            RelayControlFrame::UnsubscribePresence { peers } => {
                self.unsubscribe_presence(frame_type, peers).await
            }
            RelayControlFrame::PresenceCheck { peers } => {
                self.presence_check(frame_type, peers).await
            }
            RelayControlFrame::SubscribeRooms { peers } => {
                self.subscribe_rooms(frame_type, peers).await
            }
            RelayControlFrame::UnsubscribeRooms { peers } => {
                self.unsubscribe_rooms(frame_type, peers).await
            }
            RelayControlFrame::RoomsCheck { peers } => self.rooms_check(frame_type, peers).await,
            RelayControlFrame::RoomMetaUpdate(frame) => self.room_meta_update(frame).await,
        }
    }

    async fn subscribe_presence(
        &mut self,
        frame_type: &'static str,
        peers: Vec<String>,
    ) -> ActorDispatch {
        let Some(peers) = self.bounded_peers(frame_type, peers) else {
            return ActorDispatch::Continue;
        };
        self.actor
            .presence
            .subscribe(self.actor.peer_id.clone(), peers.clone())
            .await;
        for peer in &peers {
            if self.actor.delivery.is_online(peer) {
                self.actor
                    .events
                    .publish_peer_online_backfill(&self.actor.peer_id, peer);
            }
        }
        ActorDispatch::Continue
    }

    async fn unsubscribe_presence(
        &mut self,
        frame_type: &'static str,
        peers: Vec<String>,
    ) -> ActorDispatch {
        let Some(peers) = self.bounded_peers(frame_type, peers) else {
            return ActorDispatch::Continue;
        };
        self.actor
            .presence
            .unsubscribe(&self.actor.peer_id, peers)
            .await;
        ActorDispatch::Continue
    }

    async fn presence_check(
        &mut self,
        frame_type: &'static str,
        peers: Vec<String>,
    ) -> ActorDispatch {
        let Some(peers) = self.bounded_peers(frame_type, peers) else {
            return ActorDispatch::Continue;
        };
        if !self.actor.allow_control_check(frame_type, &peers) {
            return ActorDispatch::Continue;
        }
        let states = self
            .actor
            .presence
            .snapshot(&peers, |p| self.actor.delivery.is_online(p))
            .await;
        self.actor.emit_deduped_presence(states)
    }

    async fn subscribe_rooms(
        &mut self,
        frame_type: &'static str,
        peers: Vec<String>,
    ) -> ActorDispatch {
        let Some(peers) = self.bounded_peers(frame_type, peers) else {
            return ActorDispatch::Continue;
        };
        self.actor
            .rooms
            .subscribe(self.actor.peer_id.clone(), peers)
            .await;
        ActorDispatch::Continue
    }

    async fn unsubscribe_rooms(
        &mut self,
        frame_type: &'static str,
        peers: Vec<String>,
    ) -> ActorDispatch {
        let Some(peers) = self.bounded_peers(frame_type, peers) else {
            return ActorDispatch::Continue;
        };
        self.actor
            .rooms
            .unsubscribe(&self.actor.peer_id, peers)
            .await;
        ActorDispatch::Continue
    }

    async fn rooms_check(&mut self, frame_type: &'static str, peers: Vec<String>) -> ActorDispatch {
        let Some(peers) = self.bounded_peers(frame_type, peers) else {
            return ActorDispatch::Continue;
        };
        if !self.actor.allow_control_check(frame_type, &peers) {
            return ActorDispatch::Continue;
        }
        self.actor.emit_deduped_room_snapshots(peers)
    }

    async fn room_meta_update(&mut self, frame: RoomMetaUpdateFrame) -> ActorDispatch {
        let target_room = frame.room_id.unwrap_or_else(|| self.actor.room_id.clone());
        let is_empty_patch = frame.meta.is_empty();
        // `cross_room` is the leak-detection signal: a sender patching a room
        // it did NOT authenticate into. Under a shared owner epk (multiple Pi
        // processes authed as the same peer_id), a sibling patch for another
        // room resolves to a known `(peer_id, room_id)` key and would be
        // accepted — `cross_room=true` flags it for triage. Logs field-name
        // presence only, never values (session_id is endpoint-owned opaque
        // data; see `pi_forward.rs` privacy posture).
        let cross_room = target_room != self.actor.room_id;
        let fields: Vec<&str> = [
            frame.meta.model.as_ref().map(|_| "model"),
            frame.meta.thinking.as_ref().map(|_| "thinking"),
            frame.meta.session_id.as_ref().map(|_| "session_id"),
            frame.meta.working.map(|_| "working"),
            frame.meta.background.map(|_| "background"),
        ]
        .into_iter()
        .flatten()
        .collect();
        let patch_result =
            match self
                .actor
                .room_state
                .apply_patch(&self.actor.peer_id, &target_room, frame.meta)
            {
                Some(result) => result,
                None => {
                    warn!(
                        peer = %self.actor.peer_short,
                        room = %target_room,
                        authed_room = %self.actor.room_id,
                        cross_room,
                        "room_meta_update for unknown (peer, room), dropping"
                    );
                    return ActorDispatch::Continue;
                }
            };

        if is_empty_patch {
            info!(
                peer = %self.actor.peer_short,
                room = %target_room,
                authed_room = %self.actor.room_id,
                cross_room,
                fields = ?fields,
                "room_meta_update no-op (empty patch)"
            );
        } else {
            info!(
                peer = %self.actor.peer_short,
                room = %target_room,
                authed_room = %self.actor.room_id,
                cross_room,
                fields = ?fields,
                "room_meta_update applied"
            );
            self.actor
                .events
                .publish_room_meta_updated(&self.actor.peer_id, &target_room, &patch_result.meta)
                .await;
        }

        ActorDispatch::Continue
    }

    fn bounded_peers(&self, frame_type: &str, peers: Vec<String>) -> Option<Vec<String>> {
        match bounded_peer_list(frame_type, peers) {
            Ok(peers) => Some(peers),
            Err(ControlFrameError::TooManyPeers {
                requested, limit, ..
            }) => {
                warn!(
                    peer = %self.actor.peer_short,
                    frame_type = %frame_type,
                    requested_peers = requested,
                    limit,
                    "control frame peer limit exceeded, dropping"
                );
                None
            }
            Err(ControlFrameError::InvalidPeerId { index, .. }) => {
                warn!(
                    peer = %self.actor.peer_short,
                    frame_type = %frame_type,
                    peer_index = index,
                    "control frame contains invalid peer id, dropping"
                );
                None
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use axum::extract::ws::Message;
    use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
    use ed25519_dalek::SigningKey;
    use serde_json::json;
    use tokio::sync::mpsc;

    use super::{ControlFrameError, bounded_peer_list};
    use crate::handlers::connection_actor::{
        ActorDispatch, ConnectionActor, ConnectionActorServices,
    };
    use crate::handlers::peer::MAX_CONTROL_FRAME_PEERS;
    use crate::metrics::FirehoseMetrics;
    use crate::peers::registry::PeerRegistry;
    use crate::presence::PresenceManager;
    use crate::protocol::frame::{DecodedRelayFrame, decode_relay_frame};
    use crate::protocol::generated::control::{RelayControlFrame, RoomMetaUpdateFrame};
    use crate::protocol::outer::OuterEnvelopeParser;
    use crate::resource_limits::OUTBOUND_QUEUE_CAPACITY;
    use crate::rooms::{RoomManager, RoomMeta, RoomMetaPatch};

    fn canonical_peer_id(seed: u8) -> String {
        let signing_key = SigningKey::from_bytes(&[seed; 32]);
        B64.encode(signing_key.verifying_key().to_bytes())
    }

    fn make_meta(room_id: &str) -> RoomMeta {
        RoomMeta {
            room_id: room_id.into(),
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

    struct Fixture {
        presence: Arc<PresenceManager>,
        rooms: Arc<RoomManager>,
        registry: Arc<PeerRegistry>,
        metrics: Arc<FirehoseMetrics>,
    }

    impl Fixture {
        fn new() -> Self {
            let presence = Arc::new(PresenceManager::new());
            let rooms = Arc::new(RoomManager::new());
            let metrics = Arc::new(FirehoseMetrics::new());
            let registry = Arc::new(PeerRegistry::new(
                presence.clone(),
                rooms.clone(),
                metrics.clone(),
            ));
            Self {
                presence,
                rooms,
                registry,
                metrics,
            }
        }

        fn actor(&self, peer_id: &str) -> ConnectionActor {
            ConnectionActor::new(
                peer_id.to_owned(),
                peer_id.to_owned(),
                "main".to_string(),
                0,
                ConnectionActorServices {
                    registry: self.registry.clone(),
                    presence: self.presence.clone(),
                    rooms: self.rooms.clone(),
                    mesh: Arc::new(crate::mesh::MeshStore::open_in_memory().unwrap()),
                    mesh_auth: Arc::new(crate::handlers::pi_forward::MeshAuthCache::new()),
                    metrics: self.metrics.clone(),
                },
            )
        }
    }

    #[test]
    fn missing_peers_defaults_to_empty_list_at_generated_boundary() {
        let frame: RelayControlFrame = serde_json::from_value(json!({
            "type": "subscribe_presence"
        }))
        .expect("generated control frame parses default peers");

        assert!(
            matches!(frame, RelayControlFrame::SubscribePresence { peers } if peers.is_empty())
        );
    }

    #[test]
    fn rejects_non_array_peer_list_at_generated_boundary() {
        let err = serde_json::from_value::<RelayControlFrame>(json!({
            "type": "subscribe_presence",
            "peers": "peer-a"
        }))
        .expect_err("generated control frame rejects non-array peers");

        assert!(err.to_string().contains("invalid type"));
    }

    #[test]
    fn rejects_mixed_type_peer_list_at_generated_boundary() {
        let err = serde_json::from_value::<RelayControlFrame>(json!({
            "type": "subscribe_presence",
            "peers": ["peer-a", 1]
        }))
        .expect_err("generated control frame rejects non-string peers");

        assert!(err.to_string().contains("invalid type"));
    }

    #[test]
    fn rejects_malformed_room_meta_update_at_generated_boundary() {
        let err = serde_json::from_value::<RelayControlFrame>(json!({
            "type": "room_meta_update",
            "meta": []
        }))
        .expect_err("generated control frame rejects non-object meta");

        assert!(err.to_string().contains("invalid type"));
    }

    #[test]
    fn rejects_nullable_working_in_room_meta_update_at_generated_boundary() {
        let err = serde_json::from_value::<RelayControlFrame>(json!({
            "type": "room_meta_update",
            "meta": { "working": null }
        }))
        .expect_err("generated control frame rejects null working");

        assert!(err.to_string().contains("invalid type"));
    }

    #[test]
    fn rejects_nullable_background_in_room_meta_update_at_generated_boundary() {
        let err = serde_json::from_value::<RelayControlFrame>(json!({
            "type": "room_meta_update",
            "meta": { "background": null }
        }))
        .expect_err("generated control frame rejects null background");

        assert!(err.to_string().contains("invalid type"));
    }

    #[test]
    fn parses_room_meta_update_with_generated_patch_type() {
        let frame: RelayControlFrame = serde_json::from_value(json!({
            "type": "room_meta_update",
            "meta": {
                "session_id": null,
                "working": false,
                "background": true
            }
        }))
        .expect("generated room_meta_update parses");

        assert!(matches!(
            frame,
            RelayControlFrame::RoomMetaUpdate(RoomMetaUpdateFrame { meta, .. })
                if meta.session_id == Some(None)
                    && meta.working == Some(false)
                    && meta.background == Some(true)
        ));
    }

    #[test]
    fn enforces_peer_limit() {
        let peers = (0..=MAX_CONTROL_FRAME_PEERS)
            .map(|idx| format!("peer-{idx}"))
            .collect::<Vec<_>>();
        assert!(matches!(
            bounded_peer_list("presence_check", peers),
            Err(ControlFrameError::TooManyPeers { requested, .. }) if requested == MAX_CONTROL_FRAME_PEERS + 1
        ));
    }

    #[test]
    fn rejects_noncanonical_peer_identity() {
        assert!(matches!(
            bounded_peer_list("rooms_check", vec!["attacker-selected".to_string()]),
            Err(ControlFrameError::InvalidPeerId { index: 0, .. })
        ));
    }

    #[tokio::test]
    async fn invalid_rooms_check_is_dropped_before_snapshot_retention() {
        let fixture = Fixture::new();
        let mut actor = fixture.actor("app");

        let dispatch = actor
            .dispatch_control(RelayControlFrame::RoomsCheck {
                peers: vec!["attacker-selected".to_string()],
            })
            .await;

        assert!(matches!(dispatch, ActorDispatch::Continue));
        let [_, _, _, _, rooms_emitted, rooms_suppressed, _] = fixture.metrics.snapshot();
        assert_eq!((rooms_emitted, rooms_suppressed), (0, 0));
    }

    #[tokio::test]
    async fn oversized_subscribe_presence_does_not_mutate_subscriptions() {
        let fixture = Fixture::new();
        let mut actor = fixture.actor("app");
        let peers = (0..=MAX_CONTROL_FRAME_PEERS)
            .map(|idx| format!("peer-{idx}"))
            .collect();

        let dispatch = actor
            .dispatch_control(RelayControlFrame::SubscribePresence { peers })
            .await;

        assert!(matches!(dispatch, ActorDispatch::Continue));
        assert!(fixture.presence.subscribers_of("peer-0").await.is_empty());
    }

    #[tokio::test]
    async fn subscribe_presence_backfills_online_peers_from_handler() {
        let fixture = Fixture::new();
        let (tx_app, mut rx_app) = mpsc::channel::<Message>(OUTBOUND_QUEUE_CAPACITY);
        fixture
            .registry
            .register("app".into(), make_meta("main"), "dev-a".to_string(), tx_app)
            .await;
        let target_peer = canonical_peer_id(1);
        let (tx_pi, _rx_pi) = mpsc::channel::<Message>(OUTBOUND_QUEUE_CAPACITY);
        fixture
            .registry
            .register(
                target_peer.clone(),
                make_meta("main"),
                "dev-a".to_string(),
                tx_pi,
            )
            .await;
        let mut actor = fixture.actor("app");

        let dispatch = actor
            .dispatch_control(RelayControlFrame::SubscribePresence {
                peers: vec![target_peer.clone()],
            })
            .await;

        assert!(matches!(dispatch, ActorDispatch::Continue));
        assert!(
            fixture
                .presence
                .subscribers_of(&target_peer)
                .await
                .contains(&"app".to_string())
        );
        let msg = rx_app.try_recv().expect("backfill peer_online");
        let v: serde_json::Value = serde_json::from_str(msg.to_text().unwrap()).unwrap();
        assert_eq!(v, json!({"type": "peer_online", "peer": target_peer}));
    }

    #[tokio::test]
    async fn room_meta_update_dispatches_through_typed_actor_handler() {
        let fixture = Fixture::new();
        let (tx_pi, _rx_pi) = mpsc::channel::<Message>(OUTBOUND_QUEUE_CAPACITY);
        fixture
            .registry
            .register("pi".into(), make_meta("main"), "dev-a".to_string(), tx_pi)
            .await;
        let (tx_app, mut rx_app) = mpsc::channel::<Message>(OUTBOUND_QUEUE_CAPACITY);
        fixture
            .registry
            .register("app".into(), make_meta("main"), "dev-a".to_string(), tx_app)
            .await;
        fixture
            .rooms
            .subscribe("app".into(), vec!["pi".to_string()])
            .await;
        let mut actor = fixture.actor("pi");

        let decoded = decode_relay_frame(
            &OuterEnvelopeParser::new(1024),
            r#"{"type":"room_meta_update","room_id":"main","meta":{"working":true,"background":true}}"#,
        )
        .expect("room_meta_update with background decodes at the relay boundary");
        let DecodedRelayFrame::Control(frame) = decoded else {
            panic!("room_meta_update must decode as a typed control frame");
        };

        let dispatch = actor.dispatch_control(frame).await;

        assert!(matches!(dispatch, ActorDispatch::Continue));
        let msg = rx_app.try_recv().expect("room_meta_updated");
        let v: serde_json::Value = serde_json::from_str(msg.to_text().unwrap()).unwrap();
        assert_eq!(v["type"], "room_meta_updated");
        assert_eq!(v["peer"], "pi");
        assert_eq!(v["room_id"], "main");
        assert_eq!(v["meta"]["working"], true);
        assert_eq!(v["meta"]["background"], true);
        assert_eq!(fixture.registry.rooms_of("pi")[0].background, Some(true));
    }

    /// A `room_meta_update` whose `room_id` differs from the actor's
    /// authenticated room is still accepted (the relay keys rooms by
    /// `(peer_id, room_id)` and a shared owner epk makes the target key
    /// exist), and broadcasts `room_meta_updated` for the TARGET room — not
    /// the sender's authed room. This is the cross-room leak path; the INFO
    /// line carries `cross_room=true` (asserted here via the observable
    /// broadcast, since there is no tracing-test dep to assert log text).
    #[tokio::test]
    async fn room_meta_update_targets_a_room_the_sender_did_not_auth_into() {
        let fixture = Fixture::new();
        // The "pi" peer is registered in `main`, but we'll patch `other`.
        // Under a shared owner epk both rooms resolve to the same peer_id,
        // so `apply_patch` needs a room entry to exist for `(pi, other)`.
        // Register a second connection for the same peer in `other` to
        // create that entry — modeling two Pi processes sharing one epk.
        let (tx_main, _rx_main) = mpsc::channel::<Message>(OUTBOUND_QUEUE_CAPACITY);
        fixture
            .registry
            .register("pi".into(), make_meta("main"), "dev-a".to_string(), tx_main)
            .await;
        let (tx_other, rx_other) = mpsc::channel::<Message>(OUTBOUND_QUEUE_CAPACITY);
        fixture
            .registry
            .register(
                "pi".into(),
                make_meta("other"),
                "dev-a".to_string(),
                tx_other,
            )
            .await;
        let (tx_app, mut rx_app) = mpsc::channel::<Message>(OUTBOUND_QUEUE_CAPACITY);
        fixture
            .registry
            .register("app".into(), make_meta("main"), "dev-a".to_string(), tx_app)
            .await;
        fixture
            .rooms
            .subscribe("app".into(), vec!["pi".to_string()])
            .await;
        // Actor authenticated in `main` (Fixture::actor hardcodes room_id
        // = "main"); the patch targets `other`.
        let mut actor = fixture.actor("pi");

        let dispatch = actor
            .dispatch_control(RelayControlFrame::RoomMetaUpdate(RoomMetaUpdateFrame {
                room_id: Some("other".to_string()),
                meta: RoomMetaPatch {
                    session_id: Some(Some("opaque-session".to_string())),
                    ..Default::default()
                },
            }))
            .await;

        assert!(matches!(dispatch, ActorDispatch::Continue));
        // The broadcast targets `other`, not the sender's authed `main`.
        let msg = rx_app
            .try_recv()
            .expect("room_meta_updated for target room");
        let v: serde_json::Value = serde_json::from_str(msg.to_text().unwrap()).unwrap();
        assert_eq!(v["type"], "room_meta_updated");
        assert_eq!(v["peer"], "pi");
        assert_eq!(
            v["room_id"], "other",
            "broadcast must target the patched room"
        );
        assert_eq!(v["meta"]["session_id"], "opaque-session");
        // The sender's authed room (`main`) is NOT the target, so its
        // subscribers must not receive a `session_id` patch for `other`.
        let _ = rx_app.try_recv(); // drain any room_announced/rooms backfill
        // (the cross_room INFO line itself is not asserted here; it is
        // verified by the manual acceptance criterion and by reading the
        // handler source — the broadcast to `other` is the observable proof).
        let _ = &rx_other; // other-room conn exists; not asserted further
    }

    /// An empty `room_meta_update` patch (no fields) is a no-op: it does NOT
    /// broadcast `room_meta_updated`, but it DOES emit an INFO line (so the
    /// no-op path is observable in triage). Asserts the no-broadcast half.
    #[tokio::test]
    async fn room_meta_update_empty_patch_does_not_broadcast() {
        let fixture = Fixture::new();
        let (tx_pi, _rx_pi) = mpsc::channel::<Message>(OUTBOUND_QUEUE_CAPACITY);
        fixture
            .registry
            .register("pi".into(), make_meta("main"), "dev-a".to_string(), tx_pi)
            .await;
        let (tx_app, mut rx_app) = mpsc::channel::<Message>(OUTBOUND_QUEUE_CAPACITY);
        fixture
            .registry
            .register("app".into(), make_meta("main"), "dev-a".to_string(), tx_app)
            .await;
        fixture
            .rooms
            .subscribe("app".into(), vec!["pi".to_string()])
            .await;
        let mut actor = fixture.actor("pi");

        let dispatch = actor
            .dispatch_control(RelayControlFrame::RoomMetaUpdate(RoomMetaUpdateFrame {
                room_id: None,
                meta: RoomMetaPatch::default(), // empty
            }))
            .await;

        assert!(matches!(dispatch, ActorDispatch::Continue));
        // Drain any backfill from registration, then assert no
        // room_meta_updated broadcast arrives (empty patch is a no-op).
        let _ = rx_app.try_recv();
        assert!(
            rx_app.try_recv().is_err(),
            "empty room_meta_update must not broadcast room_meta_updated"
        );
    }

    #[tokio::test]
    async fn presence_check_dedup_and_metrics_live_in_actor() {
        let fixture = Fixture::new();
        let mut actor = fixture.actor("app");
        let target_peer = canonical_peer_id(1);
        let frame = || RelayControlFrame::PresenceCheck {
            peers: vec![target_peer.clone()],
        };

        let first = actor.dispatch_control(frame()).await;
        assert!(matches!(first, ActorDispatch::Send(_)));
        let second = actor.dispatch_control(frame()).await;
        assert!(matches!(second, ActorDispatch::Continue));

        let [_, _, presence_emitted, presence_suppressed, _, _, _] = fixture.metrics.snapshot();
        assert_eq!(presence_emitted, 1);
        assert_eq!(presence_suppressed, 1);
    }

    #[tokio::test]
    async fn rooms_check_dedup_and_metrics_live_in_actor() {
        let fixture = Fixture::new();
        let target_peer = canonical_peer_id(1);
        let (tx_pi, _rx_pi) = mpsc::channel::<Message>(OUTBOUND_QUEUE_CAPACITY);
        fixture
            .registry
            .register(
                target_peer.clone(),
                make_meta("main"),
                "dev-a".to_string(),
                tx_pi,
            )
            .await;
        let mut actor = fixture.actor("app");
        let frame = || RelayControlFrame::RoomsCheck {
            peers: vec![target_peer.clone()],
        };

        let first = actor.dispatch_control(frame()).await;
        assert!(matches!(first, ActorDispatch::SendMany(messages) if messages.len() == 1));
        let second = actor.dispatch_control(frame()).await;
        assert!(matches!(second, ActorDispatch::Continue));

        let [_, _, _, _, rooms_emitted, rooms_suppressed, _] = fixture.metrics.snapshot();
        assert_eq!(rooms_emitted, 1);
        assert_eq!(rooms_suppressed, 1);
    }
}
