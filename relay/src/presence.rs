use std::collections::HashMap;
use std::sync::Arc;

use tokio::sync::Mutex;

use crate::protocol::generated::control::RelayPresenceState;
use crate::resource_limits::MAX_PRESENCE_OFFLINE_TIMESTAMPS;
use crate::subscriptions::SubscriptionIndex;

#[derive(Debug, Default)]
struct Inner {
    subscriptions: SubscriptionIndex,
    /// Epoch-ms timestamp of the most recent disconnect for each peer.
    last_offline_ts: HashMap<String, i64>,
}

/// Owns presence subscriptions and the last offline timestamp for each peer.
#[derive(Clone, Debug, Default)]
pub struct PresenceManager {
    inner: Arc<Mutex<Inner>>,
}

/// Represents one peer's current reachability in a presence snapshot.
pub type PeerPresence = RelayPresenceState;

impl PresenceManager {
    /// Create an empty presence subscription and offline-state manager.
    pub fn new() -> Self {
        Self::default()
    }

    /// Replaces `subscriber`'s full subscription list with `peers`.
    /// Passing an empty list is equivalent to unsubscribing from everything.
    pub async fn subscribe(&self, subscriber: String, peers: Vec<String>) {
        let mut g = self.inner.lock().await;
        g.subscriptions.replace(subscriber, peers);
    }

    /// Removes `peers` from `subscriber`'s watched list.
    pub async fn unsubscribe(&self, subscriber: &str, peers: Vec<String>) {
        let mut g = self.inner.lock().await;
        g.subscriptions.remove(subscriber, peers);
    }

    /// Removes all subscriptions for `subscriber` (called on disconnect to prevent leaks).
    pub async fn unsubscribe_all(&self, subscriber: &str) {
        let mut g = self.inner.lock().await;
        g.subscriptions.remove_all(subscriber);
    }

    /// Returns everyone who subscribed to `peer`.
    pub async fn subscribers_of(&self, peer: &str) -> Vec<String> {
        let g = self.inner.lock().await;
        g.subscriptions.subscribers_of(peer)
    }

    /// Builds a presence snapshot for `peers`. `is_online` is called while holding
    /// the presence lock, keeping the snapshot consistent.
    pub async fn snapshot(
        &self,
        peers: &[String],
        is_online: impl Fn(&str) -> bool,
    ) -> Vec<PeerPresence> {
        let g = self.inner.lock().await;
        peers
            .iter()
            .map(|peer| {
                let online = is_online(peer);
                let since_ts = if online {
                    None
                } else {
                    g.last_offline_ts.get(peer.as_str()).copied()
                };
                PeerPresence {
                    peer: peer.clone(),
                    online,
                    since_ts,
                }
            })
            .collect()
    }

    /// Records when `peer` went offline (stored for `since_ts` in future snapshots).
    ///
    /// The oldest timestamp is evicted before admitting a new peer at the
    /// process-wide retention cap, preventing identity churn from growing this
    /// optional snapshot metadata without bound.
    pub async fn record_offline(&self, peer: &str, ts: i64) {
        let mut inner = self.inner.lock().await;
        if !inner.last_offline_ts.contains_key(peer)
            && inner.last_offline_ts.len() >= MAX_PRESENCE_OFFLINE_TIMESTAMPS
            && let Some(oldest_peer) = inner
                .last_offline_ts
                .iter()
                .min_by_key(|(_, timestamp)| *timestamp)
                .map(|(peer, _)| peer.clone())
        {
            inner.last_offline_ts.remove(&oldest_peer);
        }
        inner.last_offline_ts.insert(peer.to_string(), ts);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn subscribe_replaces_list() {
        let pm = PresenceManager::new();
        pm.subscribe("B".into(), vec!["A".into(), "C".into()]).await;
        assert!(pm.subscribers_of("A").await.contains(&"B".to_string()));
        assert!(pm.subscribers_of("C").await.contains(&"B".to_string()));

        // Replace: B now only watches A
        pm.subscribe("B".into(), vec!["A".into()]).await;
        assert!(pm.subscribers_of("A").await.contains(&"B".to_string()));
        assert!(!pm.subscribers_of("C").await.contains(&"B".to_string()));
    }

    #[tokio::test]
    async fn subscribe_empty_equals_unsubscribe_all() {
        let pm = PresenceManager::new();
        pm.subscribe("B".into(), vec!["A".into()]).await;
        pm.subscribe("B".into(), vec![]).await; // empty → clear all
        assert!(pm.subscribers_of("A").await.is_empty());
    }

    #[tokio::test]
    async fn unsubscribe_all_cleans_subscriber_from_sets() {
        let pm = PresenceManager::new();
        pm.subscribe("B".into(), vec!["A".into(), "C".into()]).await;
        pm.unsubscribe_all("B").await;
        assert!(pm.subscribers_of("A").await.is_empty());
        assert!(pm.subscribers_of("C").await.is_empty());
    }

    #[tokio::test]
    async fn snapshot_reflects_online_flag() {
        let pm = PresenceManager::new();
        pm.record_offline("X", 1_000_000).await;
        let states = pm.snapshot(&["X".into(), "Y".into()], |p| p == "Y").await;
        assert_eq!(states.len(), 2);
        let x = states.iter().find(|s| s.peer == "X").unwrap();
        let y = states.iter().find(|s| s.peer == "Y").unwrap();
        assert!(!x.online);
        assert_eq!(x.since_ts, Some(1_000_000));
        assert!(y.online);
        assert!(y.since_ts.is_none());
    }

    #[tokio::test]
    async fn offline_timestamp_retention_evicts_oldest_peer_at_capacity() {
        let pm = PresenceManager::new();
        for index in 0..MAX_PRESENCE_OFFLINE_TIMESTAMPS {
            pm.record_offline(&format!("peer-{index}"), index as i64)
                .await;
        }

        pm.record_offline("new-peer", MAX_PRESENCE_OFFLINE_TIMESTAMPS as i64)
            .await;

        let inner = pm.inner.lock().await;
        assert_eq!(inner.last_offline_ts.len(), MAX_PRESENCE_OFFLINE_TIMESTAMPS);
        assert!(!inner.last_offline_ts.contains_key("peer-0"));
        assert_eq!(
            inner.last_offline_ts.get("new-peer"),
            Some(&(MAX_PRESENCE_OFFLINE_TIMESTAMPS as i64))
        );
    }
}
