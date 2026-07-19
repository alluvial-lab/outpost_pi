use std::collections::HashMap;
use std::sync::{
    Mutex,
    atomic::{AtomicU64, Ordering},
};

use axum::extract::ws::Message;
use tokio::sync::mpsc;

use crate::metrics::FirehoseMetrics;

pub(crate) type RoomKey = (String, String); // (peer_id, room_id)

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub(crate) struct DeliveryReport {
    pub delivered: usize,
    pub saturated: usize,
}

impl DeliveryReport {
    pub(crate) fn accepted(self) -> bool {
        self.delivered > 0
    }
}

#[derive(Debug)]
pub(crate) struct ConnectionEntry {
    pub conn_id: u64,
    pub device_id: String,
    pub tx: mpsc::Sender<Message>,
}

#[derive(Debug)]
pub(crate) struct ConnectionInsert {
    pub peer_id: String,
    pub conn_id: u64,
    pub was_offline_before: bool,
    pub is_first_in_room: bool,
    pub superseded_existing: bool,
    /// `conn_id`s of prior connections at the same key that were closed
    /// because the new conn authenticated from the same `device_id` (a
    /// reconnect, not a genuine second device). Their `tx` senders were
    /// dropped, so their `handle_peer` tasks end and their sockets tear down
    /// immediately — no ping-timeout window.
    pub superseded_same_device_conn_ids: Vec<u64>,
}

/// Describes the observable state changes caused by removing one connection.
#[derive(Debug)]
pub struct ConnectionRemove {
    pub peer_id: String,
    pub removed_connection: bool,
    pub room_emptied: bool,
    pub peer_offlined: bool,
}

/// Owns live relay connection state and delivery over registered senders.
///
/// This table is the single source of truth for which authenticated websocket
/// connections are live at each `(peer_id, room_id)` key. It deliberately does
/// not store room metadata; [`super::rooms::RoomStateStore`] owns one canonical
/// `RoomMeta` snapshot for each live room.
#[derive(Debug)]
pub(crate) struct ConnectionRegistry {
    next_conn: AtomicU64,
    senders: Mutex<HashMap<RoomKey, Vec<ConnectionEntry>>>,
    metrics: std::sync::Arc<FirehoseMetrics>,
}

impl ConnectionRegistry {
    pub(crate) fn new(metrics: std::sync::Arc<FirehoseMetrics>) -> Self {
        Self {
            next_conn: AtomicU64::new(0),
            senders: Mutex::new(HashMap::new()),
            metrics,
        }
    }

    pub(crate) fn insert(
        &self,
        peer_id: &str,
        room_id: &str,
        device_id: &str,
        tx: mpsc::Sender<Message>,
    ) -> ConnectionInsert {
        let key = (peer_id.to_string(), room_id.to_string());
        let conn_id = self.next_conn.fetch_add(1, Ordering::Relaxed);

        let mut lock = self.senders.lock().unwrap();
        let was_offline_before = !lock.keys().any(|(p, _)| p == peer_id);
        let existing_count = lock.get(&key).map(|entries| entries.len()).unwrap_or(0);
        let is_first_in_room = existing_count == 0;

        // Close prior conn(s) from the SAME device at this key: this is a
        // reconnect (the old TCP path is typically half-open — no FIN/RST
        // reached the relay), so dropping the old `tx` tears down the old
        // socket immediately instead of waiting for the 25 s WS ping to time
        // it out. Entries with a DIFFERENT `device_id` (a genuine second
        // device of the same Owner) are left alive — multi-device-same-room
        // is a supported case.
        let mut superseded_same_device_conn_ids = Vec::new();
        if let Some(entries) = lock.get_mut(&key) {
            let before = entries.len();
            entries.retain(|entry| {
                if entry.device_id == device_id {
                    superseded_same_device_conn_ids.push(entry.conn_id);
                    false // drop: closing the old conn's `tx`
                } else {
                    true
                }
            });
            debug_assert_eq!(
                entries.len() + superseded_same_device_conn_ids.len(),
                before,
                "retain only removes matching-device entries"
            );
        }

        lock.entry(key).or_default().push(ConnectionEntry {
            conn_id,
            device_id: device_id.to_string(),
            tx,
        });

        ConnectionInsert {
            peer_id: peer_id.to_string(),
            conn_id,
            was_offline_before,
            is_first_in_room,
            superseded_existing: existing_count > 0,
            superseded_same_device_conn_ids,
        }
    }

    pub(crate) fn remove(&self, peer_id: &str, room_id: &str, conn_id: u64) -> ConnectionRemove {
        let mut lock = self.senders.lock().unwrap();
        let key = (peer_id.to_string(), room_id.to_string());
        let mut removed_connection = false;
        let mut room_emptied = false;

        if let Some(entries) = lock.get_mut(&key) {
            let before = entries.len();
            entries.retain(|entry| entry.conn_id != conn_id);
            removed_connection = entries.len() != before;
            if entries.is_empty() {
                lock.remove(&key);
                room_emptied = removed_connection;
            }
        }

        let peer_offlined = room_emptied && !lock.keys().any(|(p, _)| p == peer_id);
        ConnectionRemove {
            peer_id: peer_id.to_string(),
            removed_connection,
            room_emptied,
            peer_offlined,
        }
    }

    pub(crate) fn is_online(&self, peer_id: &str) -> bool {
        let lock = self.senders.lock().unwrap();
        lock.keys().any(|(p, _)| p == peer_id)
    }

    pub(crate) fn send_to_room(
        &self,
        dest_peer: &str,
        dest_room: &str,
        msg: Message,
        skip_conn_id: u64,
    ) -> DeliveryReport {
        let lock = self.senders.lock().unwrap();
        let key = (dest_peer.to_string(), dest_room.to_string());
        let Some(entries) = lock.get(&key) else {
            return DeliveryReport::default();
        };

        let report = deliver(entries, msg, Some(skip_conn_id));
        self.metrics
            .inc_outbound_queue_dropped(report.saturated as u64);
        report
    }

    pub(crate) fn send_to_peer(&self, peer_id: &str, msg: Message) -> DeliveryReport {
        let lock = self.senders.lock().unwrap();
        let mut report = DeliveryReport::default();
        for ((candidate, _), entries) in lock.iter() {
            if candidate == peer_id {
                report += deliver(entries, msg.clone(), None);
            }
        }
        self.metrics
            .inc_outbound_queue_dropped(report.saturated as u64);
        report
    }

    pub(crate) fn send_to_all_rooms_of(&self, peer_id: &str, msg: Message) -> DeliveryReport {
        self.send_to_peer(peer_id, msg)
    }
}

impl std::ops::AddAssign for DeliveryReport {
    fn add_assign(&mut self, rhs: Self) {
        self.delivered += rhs.delivered;
        self.saturated += rhs.saturated;
    }
}

fn deliver(entries: &[ConnectionEntry], msg: Message, skip_conn_id: Option<u64>) -> DeliveryReport {
    let mut report = DeliveryReport::default();
    for entry in entries {
        if skip_conn_id == Some(entry.conn_id) {
            continue;
        }
        match entry.tx.try_send(msg.clone()) {
            Ok(()) => report.delivered += 1,
            Err(mpsc::error::TrySendError::Full(_)) => report.saturated += 1,
            Err(mpsc::error::TrySendError::Closed(_)) => {}
        }
    }
    report
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::*;

    fn registry() -> (ConnectionRegistry, Arc<FirehoseMetrics>) {
        let metrics = Arc::new(FirehoseMetrics::new());
        (ConnectionRegistry::new(metrics.clone()), metrics)
    }

    #[test]
    fn full_mailbox_drops_newest_and_reports_saturation() {
        let (registry, metrics) = registry();
        let (tx, mut rx) = mpsc::channel(1);
        registry.insert("peer", "main", "device", tx);

        assert_eq!(
            registry.send_to_room("peer", "main", Message::Text("first".into()), u64::MAX),
            DeliveryReport {
                delivered: 1,
                saturated: 0,
            }
        );
        assert_eq!(
            registry.send_to_room("peer", "main", Message::Text("newest".into()), u64::MAX),
            DeliveryReport {
                delivered: 0,
                saturated: 1,
            }
        );
        assert_eq!(rx.try_recv().unwrap().to_text().unwrap(), "first");
        assert_eq!(metrics.snapshot()[6], 1);
    }

    #[test]
    fn healthy_device_accepts_while_sibling_mailbox_is_saturated() {
        let (registry, _) = registry();
        let (full_tx, mut full_rx) = mpsc::channel(1);
        let (healthy_tx, mut healthy_rx) = mpsc::channel(1);
        registry.insert("peer", "main", "full-device", full_tx);
        registry.insert("peer", "main", "healthy-device", healthy_tx);

        let first = registry.send_to_room("peer", "main", Message::Text("first".into()), u64::MAX);
        assert_eq!(first.delivered, 2);
        assert_eq!(healthy_rx.try_recv().unwrap().to_text().unwrap(), "first");

        let second =
            registry.send_to_room("peer", "main", Message::Text("second".into()), u64::MAX);
        assert_eq!(
            second,
            DeliveryReport {
                delivered: 1,
                saturated: 1,
            }
        );
        assert_eq!(full_rx.try_recv().unwrap().to_text().unwrap(), "first");
        assert_eq!(healthy_rx.try_recv().unwrap().to_text().unwrap(), "second");
    }
}
