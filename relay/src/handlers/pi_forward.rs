//! Relay-mediated Pi-to-Pi envelope forwarding.
//!
//! Pi-A sends a control frame:
//!
//! ```jsonc
//! { "type": "pi_envelope", "to_pc": "<Pi-B-pubkey-b64>", "envelope": { ... } }
//! ```
//!
//! The relay authenticates Pi-A via the existing challenge-response (so we
//! already trust `sender_peer_id` here), looks up the `mesh_versions` blob
//! that lists Pi-A and confirms Pi-B is in the same Owner's member list, then
//! forwards to all live Pi-B connections as:
//!
//! ```jsonc
//! { "type": "pi_envelope_in", "from_pc": "<Pi-A-pubkey>", "envelope": <verbatim> }
//! ```
//!
//! Cross-PC data-plane forwarding is peer-wide in this slice. Any `session_id`
//! inside `ct`, room metadata, or the generic `AgentEnvelope.body` is
//! endpoint-owned opaque data: this module does not parse it, derive targets
//! from it, log it, or use it as a metric key.
//!
//! Failures don't use a custom error frame — the relay synthesizes an envelope
//! with `body.type = "transport_error"`,
//! correlated to the sender's original envelope via `re: <original_id>`.

use std::collections::{HashMap, HashSet};
use std::sync::{Condvar, Mutex};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

#[cfg(test)]
use std::sync::{
    Arc, Barrier,
    atomic::{AtomicUsize, Ordering},
};
#[cfg(test)]
use std::time::Duration;

use axum::extract::ws::Message;
use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
use rand::{RngCore, thread_rng};
use tracing::{debug, warn};

use crate::mesh::{MeshStore, decode_member_keys, owner_pk_hash, verify_envelope};
use crate::peers::connections::ConnectionRegistry;
use crate::protocol::generated::cross_pc::{
    AgentEnvelope, CrossPcFrame, PiEnvelopeFrame, PiEnvelopeInFrame,
};
use crate::resource_limits::{
    MAX_CONCURRENT_MESH_AUTH_SCANS, MESH_AUTH_CACHE_CAPACITY, MESH_AUTH_CACHE_TTL,
};

/// In-memory cache that maps Pi pubkeys to verified membership or absence.
///
/// Positive and negative results share one bounded table. Cold scans are
/// single-flight per Pi key and globally admission-bounded; successful publishes
/// invalidate only entries affected by that Owner. A generation check prevents a
/// scan racing a publish from restoring stale membership.
#[derive(Debug, Default)]
pub struct MeshAuthCache {
    inner: Mutex<MeshAuthCacheInner>,
    scan_completed: Condvar,
    #[cfg(test)]
    scan_count: AtomicUsize,
    #[cfg(test)]
    active_scan_count: AtomicUsize,
    #[cfg(test)]
    max_concurrent_scan_count: AtomicUsize,
    #[cfg(test)]
    scan_delay: Mutex<Option<Duration>>,
    #[cfg(test)]
    clock: Mutex<Option<Instant>>,
    #[cfg(test)]
    publish_gate: Mutex<Option<Arc<TestScanGate>>>,
}

#[derive(Debug, Default)]
struct MeshAuthCacheInner {
    generation: u64,
    entries: HashMap<String, CacheEntry>,
    in_flight: HashSet<String>,
}

#[derive(Debug)]
struct CacheEntry {
    membership: CachedMembership,
    cached_at: Instant,
}

#[derive(Debug)]
enum CachedMembership {
    Found {
        owner_hashes: HashSet<String>,
        members: HashSet<String>,
    },
    Absent,
}

#[derive(Debug, Clone)]
struct ScannedMembership {
    owner_hashes: HashSet<String>,
    members: HashSet<String>,
}

#[cfg(test)]
#[derive(Debug)]
struct TestScanGate {
    entered: Barrier,
    release: Barrier,
}

#[cfg(test)]
struct TestActiveScanGuard<'a>(&'a AtomicUsize);

#[cfg(test)]
impl Drop for TestActiveScanGuard<'_> {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::Relaxed);
    }
}

impl MeshAuthCache {
    /// Create an empty cache; membership is populated lazily from verified mesh blobs.
    pub fn new() -> Self {
        Self::default()
    }

    /// Return verified siblings for `pi_pk`, caching both found and absent results.
    fn members_of(&self, pi_pk: &str, store: &MeshStore) -> Option<HashSet<String>> {
        loop {
            let generation = {
                let mut inner = self.inner.lock().unwrap();
                if let Some(entry) = inner.entries.get(pi_pk)
                    && self.is_fresh(entry)
                {
                    return match &entry.membership {
                        CachedMembership::Found { members, .. } => Some(members.clone()),
                        CachedMembership::Absent => None,
                    };
                }
                inner.entries.remove(pi_pk);

                if inner.in_flight.contains(pi_pk) {
                    drop(self.scan_completed.wait(inner).unwrap());
                    continue;
                }
                if inner.in_flight.len() >= MAX_CONCURRENT_MESH_AUTH_SCANS {
                    return None;
                }
                inner.in_flight.insert(pi_pk.to_string());
                inner.generation
            };

            let membership = self.scan_membership(pi_pk, store);
            #[cfg(test)]
            self.pause_before_publish();

            let mut inner = self.inner.lock().unwrap();
            inner.in_flight.remove(pi_pk);
            if inner.generation != generation {
                self.scan_completed.notify_all();
                continue;
            }

            inner.entries.retain(|_, entry| self.is_fresh(entry));
            if inner.entries.len() >= MESH_AUTH_CACHE_CAPACITY
                && !inner.entries.contains_key(pi_pk)
                && let Some(oldest) = inner
                    .entries
                    .iter()
                    .min_by_key(|(_, entry)| entry.cached_at)
                    .map(|(key, _)| key.clone())
            {
                inner.entries.remove(&oldest);
            }
            inner.entries.insert(
                pi_pk.to_string(),
                CacheEntry {
                    membership: membership
                        .clone()
                        .map_or(CachedMembership::Absent, |found| CachedMembership::Found {
                            owner_hashes: found.owner_hashes,
                            members: found.members,
                        }),
                    cached_at: self.now(),
                },
            );
            self.scan_completed.notify_all();
            return membership.map(|found| found.members);
        }
    }

    fn is_fresh(&self, entry: &CacheEntry) -> bool {
        self.now().duration_since(entry.cached_at) < MESH_AUTH_CACHE_TTL
    }

    fn now(&self) -> Instant {
        #[cfg(test)]
        if let Some(now) = *self.clock.lock().unwrap() {
            return now;
        }
        Instant::now()
    }

    fn scan_membership(&self, pi_pk: &str, store: &MeshStore) -> Option<ScannedMembership> {
        #[cfg(test)]
        let _active_scan = {
            self.scan_count.fetch_add(1, Ordering::Relaxed);
            let active = self.active_scan_count.fetch_add(1, Ordering::Relaxed) + 1;
            self.max_concurrent_scan_count
                .fetch_max(active, Ordering::Relaxed);
            if let Some(delay) = *self.scan_delay.lock().unwrap() {
                std::thread::sleep(delay);
            }
            TestActiveScanGuard(&self.active_scan_count)
        };

        let envelopes = match store.all_envelopes() {
            Ok(records) => records,
            Err(e) => {
                warn!("mesh store read failed during auth: {e}");
                return None;
            }
        };

        let mut owner_hashes = HashSet::new();
        let mut union = HashSet::new();
        for (stored_owner_hash, envelope) in envelopes {
            let header = match verify_envelope(&envelope) {
                Ok(header) => header,
                Err(err) => {
                    warn!(%err, "invalid stored mesh blob skipped during auth");
                    continue;
                }
            };
            let owner_pk_bytes = match B64.decode(&header.owner_pk) {
                Ok(bytes) => bytes,
                Err(err) => {
                    warn!(%err, "stored mesh owner key decode failed during auth");
                    continue;
                }
            };
            if owner_pk_hash(&owner_pk_bytes) != stored_owner_hash.to_lowercase() {
                warn!("stored mesh owner hash mismatch skipped during auth");
                continue;
            }

            let members = match decode_member_keys(&envelope.blob) {
                Ok(members) => members,
                Err(err) => {
                    warn!(%err, "invalid stored mesh members skipped during auth");
                    continue;
                }
            };
            if members.contains(pi_pk) {
                owner_hashes.insert(stored_owner_hash);
                union.extend(members);
            }
        }
        if owner_hashes.is_empty() {
            None
        } else {
            Some(ScannedMembership {
                owner_hashes,
                members: union,
            })
        }
    }

    /// Invalidate membership affected by one successful Owner publish.
    pub fn invalidate_owner_publish(&self, owner_hash: &str, blob: &[u8]) {
        let current_members = match decode_member_keys(blob) {
            Ok(members) => members,
            Err(err) => {
                warn!(%err, "invalid published mesh members omitted from cache invalidation");
                HashSet::new()
            }
        };
        let mut inner = self.inner.lock().unwrap();
        inner.generation = inner.generation.wrapping_add(1);
        inner.entries.retain(|pi_pk, entry| {
            if current_members.contains(pi_pk) {
                return false;
            }
            !matches!(
                &entry.membership,
                CachedMembership::Found { owner_hashes, .. }
                    if owner_hashes.contains(owner_hash)
            )
        });
    }

    /// `true` iff both Pis belong to the same Owner's mesh.
    pub fn is_authorized(&self, pi_a: &str, pi_b: &str, store: &MeshStore) -> bool {
        match self.members_of(pi_a, store) {
            Some(members) => members.contains(pi_b),
            None => false,
        }
    }

    #[cfg(test)]
    fn pause_before_publish(&self) {
        if let Some(gate) = self.publish_gate.lock().unwrap().take() {
            gate.entered.wait();
            gate.release.wait();
        }
    }
}

/// What the routing loop should do after calling `handle_pi_envelope`.
pub enum PiForwardResult {
    /// Envelope delivered (or accepted by the channel of) Pi-B.
    Forwarded,
    /// Send this message back to the original sender via their own WS sink.
    /// Always a `pi_envelope_in` whose envelope carries
    /// `body.type = "transport_error"`.
    TransportError(Message),
}

/// Handles one typed `pi_envelope` frame. `sender_peer_id` is the authenticated
/// Pi-A pubkey (already verified by the WS handshake).
pub(crate) async fn handle_pi_envelope(
    sender_peer_id: &str,
    sender_conn_id: u64,
    sender_room_id: &str,
    frame: PiEnvelopeFrame,
    delivery: &ConnectionRegistry,
    mesh: &MeshStore,
    cache: &MeshAuthCache,
) -> PiForwardResult {
    if frame.to_pc.is_empty() || frame.to_room.is_empty() {
        return PiForwardResult::TransportError(make_transport_error_from_agent(
            Some(&frame.envelope),
            sender_room_id,
            "bad_envelope",
        ));
    }

    if !cache.is_authorized(sender_peer_id, frame.to_pc.as_str(), mesh) {
        debug!(
            from_tail = %peer_tail(sender_peer_id),
            to_pc_tail = %peer_tail(&frame.to_pc),
            room = %frame.to_room,
            env_id_tail = %id_tail(&frame.envelope.id),
            "pi_envelope not_authorized",
        );
        return PiForwardResult::TransportError(make_transport_error_from_agent(
            Some(&frame.envelope),
            sender_room_id,
            "not_authorized",
        ));
    }

    let outbound = PiEnvelopeInFrame {
        from_pc: sender_peer_id.to_owned(),
        to_room: frame.to_room.clone(),
        envelope: frame.envelope,
    };
    // Capture the envelope id tail from `outbound.envelope.id` (after the
    // move above) for cross-side correlation in the debug logs below. The id
    // is expected protocol metadata (an envelope routing id), not payload;
    // only a tail is logged, never the full id.
    let env_id_tail = id_tail(&outbound.envelope.id);

    // Room-targeted delivery: only the addressed room of the destination peer
    // receives the frame, and the sender's own connection is skipped so
    // multi-device Owners don't echo their own outbound messages.
    if delivery
        .send_to_room(
            frame.to_pc.as_str(),
            frame.to_room.as_str(),
            Message::Text(
                serde_json::to_string(&CrossPcFrame::PiEnvelopeIn(outbound.clone()))
                    .expect("generated pi_envelope_in must serialize"),
            ),
            sender_conn_id,
        )
        .accepted()
    {
        debug!(
            from_tail = %peer_tail(sender_peer_id),
            to_pc_tail = %peer_tail(&frame.to_pc),
            room = %frame.to_room,
            env_id_tail = %env_id_tail,
            "pi_envelope forwarded",
        );
        PiForwardResult::Forwarded
    } else {
        debug!(
            from_tail = %peer_tail(sender_peer_id),
            to_pc_tail = %peer_tail(&frame.to_pc),
            room = %frame.to_room,
            env_id_tail = %env_id_tail,
            "pi_envelope offline (dest not found)",
        );
        PiForwardResult::TransportError(make_transport_error_from_agent(
            Some(&outbound.envelope),
            sender_room_id,
            "offline",
        ))
    }
}

/// Convert a malformed `pi_envelope` at the raw ingress escape hatch.
///
/// This boundary reads only the optional inner envelope's string `id` and
/// `from` fields so the sender can correlate a deterministic `bad_envelope`
/// transport error; all other untyped frame content remains ignored.
pub(crate) fn handle_malformed_pi_envelope(
    frame: &serde_json::Value,
    sender_room_id: &str,
) -> PiForwardResult {
    PiForwardResult::TransportError(make_transport_error_from_raw(
        frame.get("envelope"),
        sender_room_id,
        "bad_envelope",
    ))
}

fn make_pi_envelope_in(from_pc: &str, to_room: &str, envelope: AgentEnvelope) -> Message {
    let frame = CrossPcFrame::PiEnvelopeIn(PiEnvelopeInFrame {
        from_pc: from_pc.to_string(),
        to_room: to_room.to_string(),
        envelope,
    });
    Message::Text(serde_json::to_string(&frame).expect("generated pi_envelope_in must serialize"))
}

/// Builds a `pi_envelope_in` frame whose inner envelope carries
/// `body.type = "transport_error"`, correlated to the original via `re`.
fn make_transport_error_from_agent(
    envelope: Option<&AgentEnvelope>,
    to_room: &str,
    reason: &str,
) -> Message {
    let (re, to_addr) = match envelope {
        Some(envelope) => (Some(envelope.id.clone()), envelope.from.clone()),
        None => (None, "_unknown".to_string()),
    };
    make_transport_error(re, to_addr, to_room, reason)
}

fn make_transport_error_from_raw(
    envelope: Option<&serde_json::Value>,
    to_room: &str,
    reason: &str,
) -> Message {
    let (re, to_addr) = match envelope {
        Some(e) => (
            e.get("id").and_then(|v| v.as_str()).map(String::from),
            e.get("from")
                .and_then(|v| v.as_str())
                .unwrap_or("_unknown")
                .to_string(),
        ),
        None => (None, "_unknown".to_string()),
    };
    make_transport_error(re, to_addr, to_room, reason)
}

fn make_transport_error(
    re: Option<String>,
    to_addr: String,
    to_room: &str,
    reason: &str,
) -> Message {
    let err_envelope = AgentEnvelope {
        from: "_relay".to_string(),
        to: serde_json::Value::String(to_addr),
        id: make_relay_envelope_id(),
        re,
        body: serde_json::json!({ "type": "transport_error", "reason": reason }),
    };
    make_pi_envelope_in("_relay", to_room, err_envelope)
}

fn make_relay_envelope_id() -> String {
    let ts_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64;
    let mut bytes = [0u8; 16];
    thread_rng().fill_bytes(&mut bytes);

    bytes[0] = (ts_ms >> 40) as u8;
    bytes[1] = (ts_ms >> 32) as u8;
    bytes[2] = (ts_ms >> 24) as u8;
    bytes[3] = (ts_ms >> 16) as u8;
    bytes[4] = (ts_ms >> 8) as u8;
    bytes[5] = ts_ms as u8;
    bytes[6] = (bytes[6] & 0x0f) | 0x70;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    format!(
        "{:02x}{:02x}{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
        bytes[0],
        bytes[1],
        bytes[2],
        bytes[3],
        bytes[4],
        bytes[5],
        bytes[6],
        bytes[7],
        bytes[8],
        bytes[9],
        bytes[10],
        bytes[11],
        bytes[12],
        bytes[13],
        bytes[14],
        bytes[15]
    )
}

/// Last 8 chars of an envelope `id`, for cross-side correlation in `debug!`
/// logs only. The envelope `id` is expected protocol metadata (an envelope
/// routing id already used for `re` correlation), not payload; only a tail is
/// logged, never the full id.
///
/// Char-boundary-safe: the id is untrusted client-provided text and may be
/// non-ASCII or shorter than 8 chars, so byte-slicing (as the existing
/// `peer_short` helper does for pubkey-derived ASCII ids) would risk a panic
/// on a non-UTF-8 boundary. This iterates `char`s instead.
fn id_tail(id: &str) -> String {
    id.chars()
        .rev()
        .take(8)
        .collect::<String>()
        .chars()
        .rev()
        .collect()
}

/// Last 8 chars of a Pi-pubkey peer id, for `debug!` logs only. Matches the
/// `peer_short` / `dest_tail` convention (`peer.rs`, `connection_actor.rs`):
/// peer ids are Ed25519-pubkey-derived and ASCII by construction, so a tail is
/// sufficient to identify a peer in logs without logging the full key. The
/// new persistent file sink (when `OUTPOSTPI_RELAY_LOG_DIR` is set) makes
/// tail-only logging the consistent choice across INFO and DEBUG lines.
fn peer_tail(peer_id: &str) -> String {
    let len = peer_id.len();
    peer_id[len.saturating_sub(8)..].to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::PeerRegistry;
    use crate::PresenceManager;
    use crate::RoomManager;
    use ed25519_dalek::{Signer, SigningKey};
    use std::sync::Arc;

    fn fresh_cache_and_store() -> (MeshAuthCache, MeshStore) {
        (MeshAuthCache::new(), MeshStore::open_in_memory().unwrap())
    }

    fn make_owner_key() -> SigningKey {
        SigningKey::generate(&mut rand::thread_rng())
    }

    fn write_owner_blob(store: &MeshStore, owner_sk: &SigningKey, members: &[&str], version: u64) {
        let owner_pk = owner_sk.verifying_key().to_bytes();
        let pk_b64 = B64.encode(owner_pk);
        let members_json: Vec<serde_json::Value> = members
            .iter()
            .map(|m| serde_json::json!({ "remote_epk": m }))
            .collect();
        let blob = serde_json::json!({
            "owner_pk": pk_b64,
            "version": version,
            "members": members_json,
        });
        let blob_bytes = serde_json::to_vec(&blob).unwrap();
        let sig = owner_sk.sign(&blob_bytes).to_bytes();
        store
            .upsert(
                &owner_pk_hash(&owner_pk),
                &owner_pk,
                version,
                &blob_bytes,
                &sig,
                0,
            )
            .unwrap();
    }

    fn write_owner_blob_with_members_json(
        store: &MeshStore,
        owner_sk: &SigningKey,
        members: serde_json::Value,
        version: u64,
    ) {
        let owner_pk = owner_sk.verifying_key().to_bytes();
        let blob_bytes = serde_json::to_vec(&serde_json::json!({
            "owner_pk": B64.encode(owner_pk),
            "version": version,
            "members": members,
        }))
        .unwrap();
        let sig = owner_sk.sign(&blob_bytes).to_bytes();
        store
            .upsert(
                &owner_pk_hash(&owner_pk),
                &owner_pk,
                version,
                &blob_bytes,
                &sig,
                0,
            )
            .unwrap();
    }

    fn write_owner_blob_with_hash(
        store: &MeshStore,
        owner_sk: &SigningKey,
        row_owner_hash: &str,
        members: &[&str],
        version: u64,
    ) {
        let owner_pk = owner_sk.verifying_key().to_bytes();
        let pk_b64 = B64.encode(owner_pk);
        let members_json: Vec<serde_json::Value> = members
            .iter()
            .map(|m| serde_json::json!({ "remote_epk": m }))
            .collect();
        let blob = serde_json::json!({
            "owner_pk": pk_b64,
            "version": version,
            "members": members_json,
        });
        let blob_bytes = serde_json::to_vec(&blob).unwrap();
        let sig = owner_sk.sign(&blob_bytes).to_bytes();
        store
            .upsert(row_owner_hash, &owner_pk, version, &blob_bytes, &sig, 0)
            .unwrap();
    }

    fn write_invalid_owner_blob(
        store: &MeshStore,
        owner_sk: &SigningKey,
        members: &[&str],
        version: u64,
    ) {
        let owner_pk = owner_sk.verifying_key().to_bytes();
        let pk_b64 = B64.encode(owner_pk);
        let members_json: Vec<serde_json::Value> = members
            .iter()
            .map(|m| serde_json::json!({ "remote_epk": m }))
            .collect();
        let blob = serde_json::json!({
            "owner_pk": pk_b64,
            "version": version,
            "members": members_json,
        });
        let blob_bytes = serde_json::to_vec(&blob).unwrap();
        store
            .upsert(
                &owner_pk_hash(&owner_pk),
                &owner_pk,
                version,
                &blob_bytes,
                &[0u8; 64],
                0,
            )
            .unwrap();
    }

    #[tokio::test]
    async fn authorized_same_owner() {
        let (cache, store) = fresh_cache_and_store();
        let owner = make_owner_key();
        write_owner_blob(&store, &owner, &["pi_a", "pi_b"], 1);
        assert!(cache.is_authorized("pi_a", "pi_b", &store));
        assert!(cache.is_authorized("pi_b", "pi_a", &store));
    }

    #[tokio::test]
    async fn not_authorized_cross_owner() {
        let (cache, store) = fresh_cache_and_store();
        let owner_a = make_owner_key();
        let owner_b = make_owner_key();
        write_owner_blob(&store, &owner_a, &["pi_a"], 1);
        write_owner_blob(&store, &owner_b, &["pi_b"], 1);
        assert!(!cache.is_authorized("pi_a", "pi_b", &store));
        assert!(!cache.is_authorized("pi_b", "pi_a", &store));
    }

    #[test]
    fn overlapping_owner_authorization_is_insertion_order_independent() {
        for authorizing_owner_first in [false, true] {
            let (cache, store) = fresh_cache_and_store();
            let authorizing_owner = make_owner_key();
            let other_owner = make_owner_key();

            if authorizing_owner_first {
                write_owner_blob(&store, &authorizing_owner, &["pi_a", "pi_b"], 1);
                write_owner_blob(&store, &other_owner, &["pi_a", "pi_c"], 1);
            } else {
                write_owner_blob(&store, &other_owner, &["pi_a", "pi_c"], 1);
                write_owner_blob(&store, &authorizing_owner, &["pi_a", "pi_b"], 1);
            }

            assert!(
                cache.is_authorized("pi_a", "pi_b", &store),
                "any overlapping Owner mesh may authorize the destination"
            );
        }
    }

    #[test]
    fn overlapping_owner_revocation_invalidates_cached_union() {
        let (cache, store) = fresh_cache_and_store();
        let other_owner = make_owner_key();
        let authorizing_owner = make_owner_key();
        write_owner_blob(&store, &other_owner, &["pi_a", "pi_c"], 1);
        write_owner_blob(&store, &authorizing_owner, &["pi_a", "pi_b"], 1);
        assert!(cache.is_authorized("pi_a", "pi_b", &store));

        write_owner_blob(&store, &authorizing_owner, &["pi_d"], 2);
        let owner_hash = owner_pk_hash(&authorizing_owner.verifying_key().to_bytes());
        let record = store.get(&owner_hash).unwrap().unwrap();
        cache.invalidate_owner_publish(&owner_hash, &record.blob);

        assert!(cache.is_authorized("pi_a", "pi_c", &store));
        assert!(!cache.is_authorized("pi_a", "pi_b", &store));
    }

    #[tokio::test]
    async fn cache_hits_after_first_lookup() {
        let (cache, store) = fresh_cache_and_store();
        let owner = make_owner_key();
        write_owner_blob(&store, &owner, &["pi_x", "pi_y"], 1);
        assert!(cache.is_authorized("pi_x", "pi_y", &store));
        assert!(cache.is_authorized("pi_x", "pi_y", &store));
        assert_eq!(cache.scan_count.load(Ordering::Relaxed), 1);
        assert!(cache.inner.lock().unwrap().entries.contains_key("pi_x"));
    }

    #[test]
    fn positive_and_negative_membership_refresh_at_ttl() {
        let (cache, store) = fresh_cache_and_store();
        let base = Instant::now();
        *cache.clock.lock().unwrap() = Some(base);
        let owner = make_owner_key();

        write_owner_blob(&store, &owner, &["pi_a", "pi_b"], 1);
        assert!(cache.is_authorized("pi_a", "pi_b", &store));
        assert_eq!(cache.scan_count.load(Ordering::Relaxed), 1);

        *cache.clock.lock().unwrap() = Some(base + MESH_AUTH_CACHE_TTL - Duration::from_nanos(1));
        assert!(cache.is_authorized("pi_a", "pi_b", &store));
        assert_eq!(cache.scan_count.load(Ordering::Relaxed), 1);

        write_owner_blob(&store, &owner, &["pi_a", "pi_c"], 2);
        *cache.clock.lock().unwrap() = Some(base + MESH_AUTH_CACHE_TTL);
        assert!(!cache.is_authorized("pi_a", "pi_b", &store));
        assert!(cache.is_authorized("pi_a", "pi_c", &store));
        assert_eq!(cache.scan_count.load(Ordering::Relaxed), 2);

        assert!(!cache.is_authorized("pi_missing", "dest", &store));
        assert_eq!(cache.scan_count.load(Ordering::Relaxed), 3);
        *cache.clock.lock().unwrap() =
            Some(base + (MESH_AUTH_CACHE_TTL * 2) - Duration::from_nanos(1));
        assert!(!cache.is_authorized("pi_missing", "dest", &store));
        assert_eq!(cache.scan_count.load(Ordering::Relaxed), 3);

        write_owner_blob(&store, &owner, &["pi_missing", "dest"], 3);
        *cache.clock.lock().unwrap() = Some(base + (MESH_AUTH_CACHE_TTL * 2));
        assert!(cache.is_authorized("pi_missing", "dest", &store));
        assert_eq!(cache.scan_count.load(Ordering::Relaxed), 4);
        assert!(cache.inner.lock().unwrap().entries.len() <= MESH_AUTH_CACHE_CAPACITY);
    }

    #[test]
    fn concurrent_cold_misses_for_same_key_scan_once() {
        let cache = Arc::new(MeshAuthCache::new());
        let store = Arc::new(MeshStore::open_in_memory().unwrap());
        *cache.scan_delay.lock().unwrap() = Some(Duration::from_millis(25));
        let start = Arc::new(Barrier::new(17));

        std::thread::scope(|scope| {
            for _ in 0..16 {
                let cache = cache.clone();
                let store = store.clone();
                let start = start.clone();
                scope.spawn(move || {
                    start.wait();
                    assert!(!cache.is_authorized("same-absent", "dest", &store));
                });
            }
            start.wait();
        });

        assert_eq!(cache.scan_count.load(Ordering::Relaxed), 1);
    }

    #[test]
    fn distinct_cold_keys_cannot_exceed_global_scan_limit() {
        let cache = Arc::new(MeshAuthCache::new());
        let store = Arc::new(MeshStore::open_in_memory().unwrap());
        *cache.scan_delay.lock().unwrap() = Some(Duration::from_millis(100));
        let thread_count = MAX_CONCURRENT_MESH_AUTH_SCANS * 4;
        let start = Arc::new(Barrier::new(thread_count + 1));

        std::thread::scope(|scope| {
            for index in 0..thread_count {
                let cache = cache.clone();
                let store = store.clone();
                let start = start.clone();
                scope.spawn(move || {
                    start.wait();
                    assert!(!cache.is_authorized(&format!("absent-{index}"), "dest", &store));
                });
            }
            start.wait();
        });

        assert!(
            cache.max_concurrent_scan_count.load(Ordering::Relaxed)
                <= MAX_CONCURRENT_MESH_AUTH_SCANS,
            "distinct cold identities must share one process-wide scan ceiling"
        );
    }

    #[test]
    fn capacity_eviction_churn_still_scans_once_per_cold_key() {
        let cache = Arc::new(MeshAuthCache::new());
        let store = Arc::new(MeshStore::open_in_memory().unwrap());
        *cache.scan_delay.lock().unwrap() = Some(Duration::from_millis(10));
        {
            let mut inner = cache.inner.lock().unwrap();
            for index in 0..MESH_AUTH_CACHE_CAPACITY {
                inner.entries.insert(
                    format!("seed-{index}"),
                    CacheEntry {
                        membership: CachedMembership::Absent,
                        cached_at: Instant::now(),
                    },
                );
            }
        }

        for round in 0..3 {
            let key = format!("churn-{round}");
            let start = Arc::new(Barrier::new(9));
            std::thread::scope(|scope| {
                for _ in 0..8 {
                    let cache = cache.clone();
                    let store = store.clone();
                    let start = start.clone();
                    let key = key.clone();
                    scope.spawn(move || {
                        start.wait();
                        assert!(!cache.is_authorized(&key, "dest", &store));
                    });
                }
                start.wait();
            });
        }

        assert_eq!(cache.scan_count.load(Ordering::Relaxed), 3);
        assert!(cache.inner.lock().unwrap().entries.len() <= MESH_AUTH_CACHE_CAPACITY);
    }

    #[tokio::test]
    async fn malformed_member_entry_rejects_the_whole_signed_record() {
        let (cache, store) = fresh_cache_and_store();
        let owner = make_owner_key();
        write_owner_blob_with_members_json(
            &store,
            &owner,
            serde_json::json!([{"remote_epk": "pi_a"}, {"remote_epk": 7}]),
            1,
        );

        assert!(!cache.is_authorized("pi_a", "pi_b", &store));
    }

    #[test]
    fn malformed_publish_invalidates_cached_owner_without_authorizing_members() {
        let (cache, store) = fresh_cache_and_store();
        let owner = make_owner_key();
        write_owner_blob(&store, &owner, &["pi_a", "pi_b"], 1);
        assert!(cache.is_authorized("pi_a", "pi_b", &store));

        write_owner_blob_with_members_json(&store, &owner, serde_json::json!({}), 2);
        let owner_hash = owner_pk_hash(&owner.verifying_key().to_bytes());
        let record = store.get(&owner_hash).unwrap().unwrap();
        cache.invalidate_owner_publish(&owner_hash, &record.blob);

        assert!(!cache.is_authorized("pi_a", "pi_b", &store));
    }

    #[tokio::test]
    async fn invalid_stored_blob_does_not_authorize_members() {
        let (cache, store) = fresh_cache_and_store();
        let owner = make_owner_key();
        write_invalid_owner_blob(&store, &owner, &["pi_a", "pi_b"], 1);

        assert!(!cache.is_authorized("pi_a", "pi_b", &store));
        let inner = cache.inner.lock().unwrap();
        assert!(matches!(
            inner.entries.get("pi_a").map(|entry| &entry.membership),
            Some(CachedMembership::Absent)
        ));
    }

    #[tokio::test]
    async fn negative_cache_is_invalidated_after_membership_publish() {
        let (cache, store) = fresh_cache_and_store();
        assert!(!cache.is_authorized("pi_a", "pi_b", &store));

        let owner = make_owner_key();
        write_owner_blob(&store, &owner, &["pi_a", "pi_b"], 1);
        assert!(
            !cache.is_authorized("pi_a", "pi_b", &store),
            "negative result remains authoritative until publish invalidation"
        );

        let owner_hash = owner_pk_hash(&owner.verifying_key().to_bytes());
        let record = store.get(&owner_hash).unwrap().unwrap();
        cache.invalidate_owner_publish(&owner_hash, &record.blob);
        assert!(cache.is_authorized("pi_a", "pi_b", &store));
    }

    #[test]
    fn publish_racing_a_scan_cannot_restore_stale_membership() {
        let cache = Arc::new(MeshAuthCache::new());
        let store = Arc::new(MeshStore::open_in_memory().unwrap());
        let gate = Arc::new(TestScanGate {
            entered: Barrier::new(2),
            release: Barrier::new(2),
        });
        *cache.publish_gate.lock().unwrap() = Some(gate.clone());

        let cache_for_lookup = cache.clone();
        let store_for_lookup = store.clone();
        let lookup = std::thread::spawn(move || {
            cache_for_lookup.is_authorized("pi_a", "pi_b", &store_for_lookup)
        });
        gate.entered.wait();

        let owner = make_owner_key();
        write_owner_blob(&store, &owner, &["pi_a", "pi_b"], 1);
        let owner_hash = owner_pk_hash(&owner.verifying_key().to_bytes());
        let record = store.get(&owner_hash).unwrap().unwrap();
        cache.invalidate_owner_publish(&owner_hash, &record.blob);
        gate.release.wait();

        assert!(lookup.join().unwrap());
        assert_eq!(cache.scan_count.load(Ordering::Relaxed), 2);
        assert!(cache.is_authorized("pi_a", "pi_b", &store));
        assert_eq!(
            cache.scan_count.load(Ordering::Relaxed),
            2,
            "the racing retry must publish a reusable cache entry"
        );
    }

    #[test]
    fn publish_invalidation_preserves_unrelated_owner_cache_entries() {
        let (cache, store) = fresh_cache_and_store();
        let owner_a = make_owner_key();
        let owner_b = make_owner_key();
        write_owner_blob(&store, &owner_a, &["pi_a", "pi_a2"], 1);
        write_owner_blob(&store, &owner_b, &["pi_b", "pi_b2"], 1);
        assert!(cache.is_authorized("pi_a", "pi_a2", &store));
        assert!(cache.is_authorized("pi_b", "pi_b2", &store));
        assert_eq!(cache.scan_count.load(Ordering::Relaxed), 2);

        write_owner_blob(&store, &owner_a, &["pi_a", "pi_a3"], 2);
        let owner_hash = owner_pk_hash(&owner_a.verifying_key().to_bytes());
        let record = store.get(&owner_hash).unwrap().unwrap();
        cache.invalidate_owner_publish(&owner_hash, &record.blob);

        assert!(cache.is_authorized("pi_b", "pi_b2", &store));
        assert_eq!(
            cache.scan_count.load(Ordering::Relaxed),
            2,
            "publishing owner A must not evict owner B"
        );
    }

    #[test]
    fn cache_capacity_bounds_positive_and_negative_entries_together() {
        let cache = MeshAuthCache::new();
        let store = MeshStore::open_in_memory().unwrap();
        for index in 0..=MESH_AUTH_CACHE_CAPACITY {
            assert!(!cache.is_authorized(&format!("absent-{index}"), "dest", &store));
        }
        assert!(cache.inner.lock().unwrap().entries.len() <= MESH_AUTH_CACHE_CAPACITY);
    }

    #[tokio::test]
    async fn stored_owner_hash_mismatch_does_not_authorize_members() {
        let (cache, store) = fresh_cache_and_store();
        let owner = make_owner_key();
        write_owner_blob_with_hash(
            &store,
            &owner,
            "0000000000000000000000000000000000000000000000000000000000000000",
            &["pi_a", "pi_b"],
            1,
        );

        assert!(!cache.is_authorized("pi_a", "pi_b", &store));
    }

    #[tokio::test]
    async fn invalid_stored_blob_returns_not_authorized_for_pi_envelope() {
        let registry = make_registry();
        let store = MeshStore::open_in_memory().unwrap();
        let cache = MeshAuthCache::new();
        let owner = make_owner_key();
        write_invalid_owner_blob(&store, &owner, &["pi_a", "pi_b"], 1);
        let delivery = registry.connections();

        match handle_pi_envelope(
            "pi_a",
            u64::MAX,
            "main",
            valid_frame(),
            &delivery,
            &store,
            &cache,
        )
        .await
        {
            PiForwardResult::TransportError(message) => {
                let frame = transport_error_json(message);
                assert_eq!(frame["envelope"]["body"]["reason"], "not_authorized");
            }
            PiForwardResult::Forwarded => panic!("invalid stored blob must not authorize forward"),
        }
    }

    fn make_registry() -> Arc<PeerRegistry> {
        Arc::new(PeerRegistry::new(
            Arc::new(PresenceManager::new()),
            Arc::new(RoomManager::new()),
            Arc::new(crate::metrics::FirehoseMetrics::new()),
        ))
    }

    fn room_meta(room_id: &str) -> crate::rooms::RoomMeta {
        crate::rooms::RoomMeta {
            room_id: room_id.to_string(),
            name: None,
            cwd: None,
            session_id: None,
            model: None,
            thinking: None,
            working: false,
            started_at: 0,
        }
    }

    fn valid_envelope() -> AgentEnvelope {
        AgentEnvelope {
            from: "a:sess".to_string(),
            to: serde_json::Value::String("b:agent".to_string()),
            id: "018f4444-4444-7444-8444-444444444444".to_string(),
            re: None,
            body: serde_json::json!({ "type": "ping", "session_id": "opaque-session" }),
        }
    }

    fn valid_frame() -> PiEnvelopeFrame {
        PiEnvelopeFrame {
            to_pc: "pi_b".to_string(),
            to_room: "main".to_string(),
            envelope: valid_envelope(),
        }
    }

    fn transport_error_json(message: Message) -> serde_json::Value {
        let Message::Text(text) = message else {
            panic!("transport_error must be a text frame");
        };
        serde_json::from_str(&text).unwrap()
    }

    async fn typed_transport_error_reason(frame: PiEnvelopeFrame) -> String {
        let registry = make_registry();
        let store = MeshStore::open_in_memory().unwrap();
        let cache = MeshAuthCache::new();
        let delivery = registry.connections();
        match handle_pi_envelope("pi_a", u64::MAX, "main", frame, &delivery, &store, &cache).await {
            PiForwardResult::TransportError(message) => {
                transport_error_json(message)["envelope"]["body"]["reason"]
                    .as_str()
                    .unwrap()
                    .to_string()
            }
            PiForwardResult::Forwarded => panic!("must be transport_error"),
        }
    }

    fn malformed_transport_error_reason(frame: serde_json::Value) -> String {
        match handle_malformed_pi_envelope(&frame, "main") {
            PiForwardResult::TransportError(message) => {
                transport_error_json(message)["envelope"]["body"]["reason"]
                    .as_str()
                    .unwrap()
                    .to_string()
            }
            PiForwardResult::Forwarded => panic!("must be transport_error"),
        }
    }

    #[tokio::test]
    async fn typed_bad_envelope_when_to_pc_empty() {
        let mut frame = valid_frame();
        frame.to_pc.clear();
        assert_eq!(typed_transport_error_reason(frame).await, "bad_envelope");
    }

    #[tokio::test]
    async fn typed_bad_envelope_when_to_room_empty() {
        let mut frame = valid_frame();
        frame.to_room.clear();
        assert_eq!(typed_transport_error_reason(frame).await, "bad_envelope");
    }

    #[test]
    fn malformed_bad_envelope_when_missing_to_pc() {
        let frame = serde_json::json!({ "type": "pi_envelope" });
        assert_eq!(malformed_transport_error_reason(frame), "bad_envelope");
    }

    #[test]
    fn malformed_bad_envelope_when_envelope_is_not_object() {
        let frame = serde_json::json!({
            "type": "pi_envelope",
            "to_pc": "pi_b",
            "envelope": "not-an-envelope",
        });
        assert_eq!(malformed_transport_error_reason(frame), "bad_envelope");
    }

    #[tokio::test]
    async fn valid_frame_reaches_authorization_without_reading_body_session_id() {
        assert_eq!(
            typed_transport_error_reason(valid_frame()).await,
            "not_authorized"
        );
    }

    #[tokio::test]
    async fn authorized_offline_peer_returns_transport_error_offline() {
        let registry = make_registry();
        let store = MeshStore::open_in_memory().unwrap();
        let cache = MeshAuthCache::new();
        let owner = make_owner_key();
        write_owner_blob(&store, &owner, &["pi_a", "pi_b"], 1);
        let delivery = registry.connections();

        match handle_pi_envelope(
            "pi_a",
            u64::MAX,
            "main",
            valid_frame(),
            &delivery,
            &store,
            &cache,
        )
        .await
        {
            PiForwardResult::TransportError(message) => {
                let frame = transport_error_json(message);
                assert_eq!(frame["envelope"]["body"]["reason"], "offline");
                assert_eq!(
                    frame["envelope"]["re"].as_str(),
                    Some("018f4444-4444-7444-8444-444444444444")
                );
                assert_eq!(frame["envelope"]["to"].as_str(), Some("a:sess"));
            }
            PiForwardResult::Forwarded => panic!("offline peer must return transport_error"),
        }
    }

    #[tokio::test]
    async fn authorized_forward_targets_only_addressed_room() {
        let registry = make_registry();
        let (tx_main, mut rx_main) = tokio::sync::mpsc::channel::<Message>(16);
        let (tx_work, mut rx_work) = tokio::sync::mpsc::channel::<Message>(16);
        let _ = registry
            .register(
                "pi_b".to_string(),
                room_meta("main"),
                "dev-a".to_string(),
                tx_main,
            )
            .await;
        let _ = registry
            .register(
                "pi_b".to_string(),
                room_meta("work"),
                "dev-a".to_string(),
                tx_work,
            )
            .await;

        let store = MeshStore::open_in_memory().unwrap();
        let cache = MeshAuthCache::new();
        let owner = make_owner_key();
        write_owner_blob(&store, &owner, &["pi_a", "pi_b"], 1);
        // Address the frame to the "work" room only.
        let mut frame = valid_frame();
        frame.to_room = "work".to_string();
        let expected_envelope = serde_json::to_value(&frame.envelope).unwrap();
        let delivery = registry.connections();

        match handle_pi_envelope("pi_a", u64::MAX, "main", frame, &delivery, &store, &cache).await {
            PiForwardResult::Forwarded => {}
            PiForwardResult::TransportError(_) => {
                panic!("authorized room-targeted forward should deliver")
            }
        }

        // Only the addressed "work" room receives the frame; "main" does not.
        let Message::Text(text) = rx_work.try_recv().unwrap() else {
            panic!("forwarded message to work must be text");
        };
        let forwarded: serde_json::Value = serde_json::from_str(&text).unwrap();
        assert_eq!(forwarded["type"], "pi_envelope_in");
        assert_eq!(forwarded["from_pc"], "pi_a");
        assert_eq!(forwarded["to_room"], "work");
        assert_eq!(forwarded["envelope"], expected_envelope);
        assert!(
            rx_main.try_recv().is_err(),
            "room-targeted forward must not deliver to the non-addressed \"main\" room"
        );
    }

    #[tokio::test]
    async fn authorization_uses_authenticated_sender_peer_id_not_envelope_from() {
        let registry = make_registry();
        let (tx, mut rx) = tokio::sync::mpsc::channel::<Message>(16);
        let _ = registry
            .register(
                "pi_b".to_string(),
                room_meta("main"),
                "dev-a".to_string(),
                tx,
            )
            .await;

        let store = MeshStore::open_in_memory().unwrap();
        let cache = MeshAuthCache::new();
        let owner = make_owner_key();
        write_owner_blob(&store, &owner, &["pi_a", "pi_b"], 1);

        let mut frame = valid_frame();
        frame.envelope.from = "human-readable-spoof:sess".to_string();
        let expected_from = frame.envelope.from.clone();
        let delivery = registry.connections();

        match handle_pi_envelope("pi_a", u64::MAX, "main", frame, &delivery, &store, &cache).await {
            PiForwardResult::Forwarded => {}
            PiForwardResult::TransportError(_) => {
                panic!("authenticated sender peer id must authorize this forward")
            }
        }

        let Message::Text(text) = rx.try_recv().unwrap() else {
            panic!("forwarded message must be text");
        };
        let forwarded: serde_json::Value = serde_json::from_str(&text).unwrap();
        assert_eq!(forwarded["from_pc"], "pi_a");
        assert_eq!(forwarded["envelope"]["from"], expected_from);
    }

    // --- id_tail / peer_tail helpers ---------------------------------------
    // `id_tail` processes untrusted client-provided envelope ids. Byte-slicing
    // (the pattern `peer_short` uses for pubkey-derived ASCII ids) would panic
    // on a non-UTF-8 boundary; `id_tail` must be char-boundary-safe.

    #[test]
    fn id_tail_normal_uuid() {
        assert_eq!(id_tail("018f4444-4444-7444-8444-444444444444"), "44444444");
    }

    #[test]
    fn id_tail_shorter_than_eight_chars_returns_whole_id() {
        assert_eq!(id_tail("abc"), "abc");
    }

    #[test]
    fn id_tail_empty_returns_empty() {
        assert_eq!(id_tail(""), "");
    }

    #[test]
    fn id_tail_exactly_eight_chars() {
        assert_eq!(id_tail("12345678"), "12345678");
    }

    #[test]
    fn id_tail_non_ascii_does_not_panic_and_returns_char_tail() {
        // A non-ASCII id where byte-slicing at `len-8` would land mid-codepoint
        // (byte 10 sits inside the 😂 codepoint at bytes 8-11). The char-safe
        // helper must not panic; since the id has only 6 chars, the whole id is
        // returned (fewer than 8 chars → no truncation).
        let id = "😀😁😂🚀ab";
        let tail = id_tail(id);
        assert_eq!(tail, "😀😁😂🚀ab");
    }

    #[test]
    fn id_tail_non_ascii_long_truncates_to_eight_chars() {
        // 9 black stars (U+2605, 3 bytes each = 27 bytes). Byte-slicing at
        // `len-8 = 19` would land mid-codepoint (byte 19 is inside the 7th
        // star, bytes 18-20) → panic. The char-safe helper returns the last 8
        // chars. This is the regression case for the untrusted-input DoS with
        // a >8-char id (actual truncation, not the under-8 passthrough).
        let id = "★★★★★★★★★";
        let tail = id_tail(id);
        assert_eq!(tail, "★★★★★★★★");
    }

    #[test]
    fn id_tail_non_ascii_short_returns_whole_id() {
        // Fewer than 8 chars, all non-ASCII: must not slice into a codepoint.
        let id = "😀😁";
        assert_eq!(id_tail(id), "😀😁");
    }

    #[test]
    fn peer_tail_short_pubkey_returns_whole_id() {
        // Peer ids are ASCII by construction, but the helper must still be safe.
        assert_eq!(peer_tail("pi_a"), "pi_a");
    }

    #[test]
    fn peer_tail_normal_pubkey() {
        assert_eq!(peer_tail("pi_abcdefgh"), "abcdefgh");
    }
}
