//! Compile-time resource policy for relay connection and routing owners.

use std::time::Duration;

use tokio::time::Instant;

/// Deadline applied independently to the hello and auth handshake steps.
pub const HANDSHAKE_STEP_TIMEOUT: Duration = Duration::from_secs(5);
/// Number of frames retained for one authenticated connection's outbound mailbox.
pub const OUTBOUND_QUEUE_CAPACITY: usize = 16;
/// Maximum positive and negative mesh-membership entries retained together.
pub const MESH_AUTH_CACHE_CAPACITY: usize = 1_024;
/// Freshness window for positive and negative mesh-membership entries.
pub const MESH_AUTH_CACHE_TTL: Duration = Duration::from_secs(60);
/// Admission window for authenticated cross-PC forwarding attempts.
pub const PI_FORWARD_WINDOW: Duration = Duration::from_secs(60);
/// Maximum cross-PC forwarding attempts accepted per connection and window.
pub const MAX_PI_FORWARDS_PER_WINDOW: usize = 256;
/// Maximum peer IDs accepted in one presence/rooms control frame.
pub const MAX_CONTROL_FRAME_PEERS: usize = 64;
/// Maximum presence/rooms peer-cost accepted per connection and window.
pub const MAX_CONTROL_CHECK_PEER_COST_PER_WINDOW: usize = MAX_CONTROL_FRAME_PEERS * 4;
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
