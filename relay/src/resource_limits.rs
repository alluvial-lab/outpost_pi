//! Compile-time resource policy for relay connection and routing owners.

use std::time::Duration;

use tokio::time::Instant;

use crate::protocol::generated::limits::RELAY_MAX_PRE_AUTH_FRAME_BYTES;

/// Maximum WebSocket message bytes admitted before peer authentication.
pub const PRE_AUTH_MESSAGE_MAX_BYTES: usize = RELAY_MAX_PRE_AUTH_FRAME_BYTES;
/// Deadline applied independently to the hello and auth handshake steps.
/// DIAGNOSTIC (pairing-e2e flake): temporarily 30s (from 5s) to test whether
/// the app's auth send is being delayed past the original 5s deadline under CI
/// load (Dart event-loop congestion) — which would make the relay give up while
/// the app's optimistic post-auth pairing stalls. If the flake vanishes at 30s,
/// app-auth-delay is confirmed and the fix is app-side (fail-fast/retry on
/// relay close) or a principled timeout revision. REVERT after the test.
pub const HANDSHAKE_STEP_TIMEOUT: Duration = Duration::from_secs(30);
/// Number of frames retained for one authenticated connection's outbound mailbox.
pub const OUTBOUND_QUEUE_CAPACITY: usize = 16;
/// Maximum positive and negative mesh-membership entries retained together.
pub const MESH_AUTH_CACHE_CAPACITY: usize = 1_024;
/// Freshness window for positive and negative mesh-membership entries.
pub const MESH_AUTH_CACHE_TTL: Duration = Duration::from_secs(60);
/// Maximum cold mesh-membership scans admitted across the relay process at once.
pub const MAX_CONCURRENT_MESH_AUTH_SCANS: usize = 4;
/// Maximum Owner records retained in the mesh-membership database.
pub const MAX_MESH_OWNER_ROWS: usize = 1_024;
/// Maximum variable-field bytes retained across all mesh Owner records.
pub const MAX_MESH_RETAINED_BYTES: usize = 64 * 1024 * 1024;
/// Admission window for creating previously unseen mesh Owners.
pub const NEW_MESH_OWNER_WINDOW: Duration = Duration::from_secs(60);
/// Maximum previously unseen mesh Owners admitted per process and window.
pub const MAX_NEW_MESH_OWNERS_PER_WINDOW: usize = 32;
/// Admission window for authenticated cross-PC forwarding attempts.
pub const PI_FORWARD_WINDOW: Duration = Duration::from_secs(60);
/// Maximum cross-PC forwarding attempts accepted per connection and window.
pub const MAX_PI_FORWARDS_PER_WINDOW: usize = 256;
/// Maximum offline peer timestamps retained for presence snapshots.
pub const MAX_PRESENCE_OFFLINE_TIMESTAMPS: usize = 1_024;
/// Maximum peer IDs accepted in one presence/rooms control frame.
pub const MAX_CONTROL_FRAME_PEERS: usize = 64;
/// Maximum presence/rooms peer-cost accepted per connection and window.
pub const MAX_CONTROL_CHECK_PEER_COST_PER_WINDOW: usize = MAX_CONTROL_FRAME_PEERS * 4;
/// Maximum target peers retained in one connection's rooms-response dedup cache.
pub const ROOMS_DEDUP_CACHE_MAX_ENTRIES: usize = MAX_CONTROL_FRAME_PEERS;
/// Maximum peer-key and response bytes retained in one rooms-response dedup cache.
pub const ROOMS_DEDUP_CACHE_MAX_BYTES: usize = 256 * 1024;
/// Admission window for presence/rooms peer-cost checks.
pub const CONTROL_CHECK_PEER_COST_WINDOW: Duration = Duration::from_secs(60);

/// Fixed-window budget with checked cost accounting and lazy rollover.
#[derive(Debug)]
pub(crate) struct FixedWindowBudget {
    window_started: Instant,
    used: usize,
    window: Duration,
    limit: usize,
}

impl FixedWindowBudget {
    pub(crate) fn new(window: Duration, limit: usize) -> Self {
        Self {
            window_started: Instant::now(),
            used: 0,
            window,
            limit,
        }
    }

    pub(crate) fn allow(&mut self, cost: usize) -> bool {
        let now = Instant::now();
        if now.duration_since(self.window_started) >= self.window {
            self.window_started = now;
            self.used = 0;
        }

        let Some(next) = self.used.checked_add(cost) else {
            return false;
        };
        if next > self.limit {
            return false;
        }
        self.used = next;
        true
    }

    #[cfg(test)]
    pub(crate) fn used(&self) -> usize {
        self.used
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test(start_paused = true)]
    async fn fixed_window_accepts_exact_budget_and_rejects_overflow() {
        let mut budget = FixedWindowBudget::new(Duration::from_secs(60), 4);
        assert!(budget.allow(4));
        assert!(!budget.allow(1));
        assert_eq!(budget.used(), 4);
    }

    #[tokio::test(start_paused = true)]
    async fn fixed_window_rejects_arithmetic_overflow() {
        let mut budget = FixedWindowBudget::new(Duration::from_secs(60), usize::MAX);
        assert!(budget.allow(usize::MAX));
        assert!(!budget.allow(1));
    }

    #[tokio::test(start_paused = true)]
    async fn fixed_window_rolls_over_without_a_cleanup_task() {
        let mut budget = FixedWindowBudget::new(Duration::from_secs(60), 1);
        assert!(budget.allow(1));
        assert!(!budget.allow(1));
        tokio::time::advance(Duration::from_secs(60)).await;
        assert!(budget.allow(1));
    }
}
