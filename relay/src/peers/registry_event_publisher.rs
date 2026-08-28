use std::sync::Arc;

use axum::extract::ws::Message;

use super::connections::ConnectionRegistry;
use super::presence_state::PresenceTransition;
use super::rooms::RoomEnded;
use crate::metrics::FirehoseMetrics;
use crate::presence::PresenceManager;
use crate::protocol::generated::control::RelayServerControlFrame;
use crate::rooms::{RoomManager, RoomMeta};

/// Serializes and delivers registry lifecycle events to subscribed peers.
///
/// State modules return transition records; this adapter owns subscriber lookup,
/// relay-event JSON construction, firehose metrics, and delivery over the live
/// connection table. Delivery uses bounded drop-newest mailboxes and never
/// inspects message contents.
#[derive(Debug)]
pub(crate) struct RegistryEventPublisher {
    delivery: Arc<ConnectionRegistry>,
    presence: Arc<PresenceManager>,
    rooms: Arc<RoomManager>,
    metrics: Arc<FirehoseMetrics>,
}

impl RegistryEventPublisher {
    pub(crate) fn new(
        delivery: Arc<ConnectionRegistry>,
        presence: Arc<PresenceManager>,
        rooms: Arc<RoomManager>,
        metrics: Arc<FirehoseMetrics>,
    ) -> Self {
        Self {
            delivery,
            presence,
            rooms,
            metrics,
        }
    }

    pub(crate) async fn publish_room_announced(&self, peer_id: &str, room: &RoomMeta) {
        let room_subs = self.rooms.subscribers_of(peer_id).await;
        if room_subs.is_empty() {
            return;
        }

        let msg = serde_json::to_string(&RelayServerControlFrame::RoomAnnounced {
            peer: peer_id.to_string(),
            room: room.clone(),
        })
        .expect("generated room_announced serialization is infallible");
        self.publish_to_subscribers(&room_subs, msg);
    }

    pub(crate) async fn publish_room_ended(&self, peer_id: &str, ended: RoomEnded) {
        let room_subs = self.rooms.subscribers_of(peer_id).await;
        if room_subs.is_empty() {
            return;
        }

        let msg = serde_json::to_string(&RelayServerControlFrame::RoomEnded {
            peer: peer_id.to_string(),
            room_id: ended.room_id,
            since_ts: ended.since_ts,
        })
        .expect("generated room_ended serialization is infallible");
        self.publish_to_subscribers(&room_subs, msg);
    }

    pub(crate) async fn publish_presence_transition(&self, transition: PresenceTransition) {
        match transition {
            PresenceTransition::BecameOnline { peer_id } => {
                let pres_subs = self.presence.subscribers_of(&peer_id).await;
                let sub_count = pres_subs.len() as u64;
                if sub_count == 0 {
                    return;
                }

                let msg =
                    serde_json::to_string(&RelayServerControlFrame::PeerOnline { peer: peer_id })
                        .expect("generated peer_online serialization is infallible");
                self.publish_to_subscribers(&pres_subs, msg);
                self.metrics.inc_peer_online_emitted(sub_count);
            }
            PresenceTransition::StayedOnline { peer_id } => {
                let sub_count = self.presence.subscribers_of(&peer_id).await.len() as u64;
                if sub_count > 0 {
                    self.metrics.inc_peer_online_suppressed(sub_count);
                }
            }
            PresenceTransition::BecameOffline { peer_id, since_ts } => {
                let pres_subs = self.presence.subscribers_of(&peer_id).await;
                if !pres_subs.is_empty() {
                    let msg = serde_json::to_string(&RelayServerControlFrame::PeerOffline {
                        peer: peer_id.clone(),
                        since_ts,
                    })
                    .expect("generated peer_offline serialization is infallible");
                    self.publish_to_subscribers(&pres_subs, msg);
                }
                self.presence.record_offline(&peer_id, since_ts).await;
                self.presence.unsubscribe_all(&peer_id).await;
            }
            PresenceTransition::StayedOnlineAfterDisconnect { .. } => {}
        }
    }

    pub(crate) async fn publish_room_meta_updated(
        &self,
        peer_id: &str,
        room_id: &str,
        snapshot: &RoomMeta,
    ) {
        let room_subs = self.rooms.subscribers_of(peer_id).await;
        if room_subs.is_empty() {
            return;
        }

        // `room_meta_updated` is schema-defined for relay ingress and the
        // generated patch type owns its field validation. This publisher
        // serializes the post-merge snapshot because the relay emits this
        // subscriber update as a derived compatibility projection.
        let mut meta_obj = serde_json::Map::new();
        if let Some(model) = &snapshot.model {
            meta_obj.insert(
                "model".to_string(),
                serde_json::Value::String(model.clone()),
            );
        }
        if let Some(thinking) = &snapshot.thinking {
            meta_obj.insert(
                "thinking".to_string(),
                serde_json::Value::String(thinking.clone()),
            );
        }
        if let Some(session_id) = &snapshot.session_id {
            meta_obj.insert(
                "session_id".to_string(),
                serde_json::Value::String(session_id.clone()),
            );
        }
        // `working` is always present (non-nullable bool), so it always rides
        // along in the broadcast — subscribers can rely on it. `background`
        // is optional for compatibility with older hello frames.
        meta_obj.insert(
            "working".to_string(),
            serde_json::Value::Bool(snapshot.working),
        );
        if let Some(background) = snapshot.background {
            meta_obj.insert(
                "background".to_string(),
                serde_json::Value::Bool(background),
            );
        }
        let msg = serde_json::json!({
            "type": "room_meta_updated",
            "peer": peer_id,
            "room_id": room_id,
            "meta": serde_json::Value::Object(meta_obj),
        })
        .to_string();
        self.publish_to_subscribers(&room_subs, msg);
    }

    pub(crate) fn publish_peer_online_backfill(&self, subscriber: &str, peer_id: &str) {
        let msg = serde_json::to_string(&RelayServerControlFrame::PeerOnline {
            peer: peer_id.to_string(),
        })
        .expect("generated peer_online serialization is infallible");
        self.send_to_all_rooms_of(subscriber, Message::Text(msg));
    }

    fn publish_to_subscribers(&self, subscribers: &[String], msg: String) {
        for subscriber in subscribers {
            self.send_to_all_rooms_of(subscriber, Message::Text(msg.clone()));
        }
    }

    fn send_to_all_rooms_of(&self, peer_id: &str, msg: Message) {
        let _ = self.delivery.send_to_all_rooms_of(peer_id, msg);
    }
}
