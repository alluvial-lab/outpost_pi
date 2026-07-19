---
id: feature-relay-resource-bounds
kind: feature
stage: done
tags: [relay, security]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-15
updated: 2026-07-18
---

# Relay: bound unauthenticated/authenticated resource consumption and retained state

## Brief

Four security gate findings describe unbounded resource consumption on the
relay — an unauthenticated client can hold sockets/tasks open indefinitely,
authenticated senders can grow memory without limit, and the auth path scans
persisted mesh storage on every miss. Together these are DoS / resource-exhaustion
vectors. This feature bounds each:

- `gate-security-auth-challenge-no-timeout` — unauthenticated clients can hold pre-auth sockets/tasks open indefinitely
- `gate-security-pi-envelope-auth-scan-rate-limit` — every `pi_envelope` auth miss falls through to `store.all_envelopes()` and scans persisted mesh blobs
- `gate-security-subscription-empty-target-retention` — repeated subscribe/replace calls with new target names grow memory indefinitely
- `gate-security-unbounded-outbound-queues` — authenticated senders enqueue forwarded messages faster than a slow recipient drains

## Simplification opportunity

Add pre-auth timeouts/ceilings, a negative cache + per-frame limiter on the
envelope-auth path, retention bounds on subscription target maps, and a bounded
outbound queue with backpressure/drop policy. Behavior change: resource
exhaustion now fails closed (drop/disconnect) instead of growing unbounded.

## Source

Promoted from backlog by `scope` (2026-07-15). 4 `gate-security-*` findings
(auth-challenge, pi-envelope-auth-scan, subscription-retention,
unbounded-outbound-queues) from the v0.6.0 release `gate-security` pass.

## Design decisions

- **Scope of rate limiting**: enforce a per-authenticated-connection
  `pi_envelope` budget, not a process-global IP map — the expensive operation is
  mesh authorization for one authenticated sender; an IP map introduces NAT
  collateral and another retained-state table. The negative cache and bounded
  queue independently cap process-wide memory.
- **Limit configuration**: keep conservative compile-time relay policy in one
  `resource_limits` module: 5 seconds per handshake step, 256 cross-PC forward
  attempts per 60 seconds, 1,024 mesh-auth cache entries with a 60-second TTL,
  and 16 queued outbound frames per connection. These are operator-safe defaults,
  not a new public configuration surface; revisit only with measured legitimate
  traffic evidence.
- **Queue saturation policy**: bounded mailboxes use non-blocking `try_send` and
  drop the newest frame when full; they do not await while holding registry
  state and do not disconnect a healthy recipient merely because another
  authenticated client produced a burst. Saturation is counted in aggregate.
  A `pi_envelope` accepted by no destination mailbox keeps the existing
  `offline` transport error rather than expanding the generated wire enum.
- **Cache freshness**: cache both found and absent source memberships, bound the
  combined cache, and invalidate the whole cache after every successful mesh
  publish. Whole-cache invalidation is intentionally simpler and safer than
  reverse indexes; a generation check prevents a scan racing a publish from
  re-inserting stale membership.
- **Subscription identity validation**: retain the existing 64-target frame
  ceiling and canonical decoded strings; delete empty reverse-map keys rather
  than adding a second peer-ID validator. Authenticated peer IDs are already
  canonicalized at handshake, and WebSocket framing bounds individual input;
  the demonstrated leak is retained empty keys, not current live edges.
- **Protocol and persistence**: no schema, cross-language wire, database, or
  offline-delivery change. Overload is handled using existing drop/`offline`
  behavior; the relay remains payload-stateless.
- **Execution ownership**: direct-read design over the relay actor, mesh cache,
  subscription index, connection registry, and focused tests. The four existing
  child stories are sufficient design checkpoints; no extra story or parallel
  implementation ownership is justified.

## Architectural choice

### Option A — bounded local primitives at the existing ownership seams (chosen)

Put constants and a small fixed-window budget in one relay resource-policy
module; apply the handshake deadline in the socket owner, negative-cache bounds
in `MeshAuthCache`, reverse-edge cleanup in `SubscriptionIndex`, and bounded
mailboxes in `ConnectionRegistry`. This preserves current routing and generated
wire contracts while making each current owner responsible for its resource.
It optimizes for a small, auditable patch and deterministic regression tests.

### Option B — one global admission-control service

Create an `Arc<ResourceGovernor>` in `AppState` tracking IP, peer, auth, queue,
and subscription budgets. This can offer coordinated process-wide fairness, but
it creates a new global mutable table, eviction policy, and NAT behavior before
there is traffic evidence to tune them. It is more machinery than the four
verified findings require.

### Option C — redesign mesh authorization and delivery storage

Normalize signed mesh membership into indexed SQLite rows and replace the
registry with dedicated per-peer writer tasks/backpressure. This removes the
scan algorithm and could support byte-weighted fairness, but requires a storage
migration and much wider lifecycle/protocol verification. It is disproportionate
for a relay whose signed blob remains the membership authority.

**Choice:** Option A. It fails closed at the exact boundaries that currently
grow, avoids a new retained-state governor, preserves the Owner-signed blob as
authority, and leaves global/IP fairness reversible if operational evidence
later warrants it.

## Implementation Units

### Unit 1: Central relay resource policy and reusable fixed-window budget

**Files**: `relay/src/resource_limits.rs` (new), `relay/src/lib.rs`

**Stories**: shared support for all four existing checkpoints

```rust
use std::time::Duration;
use tokio::time::Instant;

pub const HANDSHAKE_STEP_TIMEOUT: Duration = Duration::from_secs(5);
pub const OUTBOUND_QUEUE_CAPACITY: usize = 16;
pub const MESH_AUTH_CACHE_CAPACITY: usize = 1_024;
pub const MESH_AUTH_CACHE_TTL: Duration = Duration::from_secs(60);
pub const PI_FORWARD_WINDOW: Duration = Duration::from_secs(60);
pub const MAX_PI_FORWARDS_PER_WINDOW: usize = 256;

pub(crate) struct FixedWindowBudget {
    window_started: Instant,
    used: usize,
    window: Duration,
    limit: usize,
}

impl FixedWindowBudget {
    pub(crate) fn new(window: Duration, limit: usize) -> Self;
    pub(crate) fn allow(&mut self, cost: usize) -> bool;
}
```

**Implementation Notes**:
- Move the existing control-check fixed-window arithmetic onto
  `FixedWindowBudget`; retain `MAX_CONTROL_FRAME_PEERS` and its existing budget
  as policy constants in this module. This consolidates, rather than duplicates,
  limiter logic.
- `allow` uses `checked_add`, resets after the configured window, and rejects
  overflow. No background task or global cleanup lifecycle is introduced.
- Re-export only constants required by integration tests; keep the limiter
  crate-private.

**Acceptance Criteria**:
- [ ] One implementation owns fixed-window rollover and checked budget addition.
- [ ] Existing control-check limits and behavior remain unchanged.
- [ ] Tests cover exact-budget acceptance, over-budget rejection, overflow
      rejection, and rollover with paused Tokio time.

---

### Unit 2: Bound both unauthenticated handshake waits

**Files**: `relay/src/auth/challenge.rs`, `relay/src/handlers/peer.rs`,
`relay/tests/integration.rs`

**Story**: `gate-security-auth-challenge-no-timeout`

```rust
async fn next_handshake_text<S, E>(stream: &mut S) -> Option<String>
where
    S: futures_util::Stream<Item = Result<axum::extract::ws::Message, E>> + Unpin;
```

**Implementation Notes**:
- Replace the hello-only millisecond constant with
  `resource_limits::HANDSHAKE_STEP_TIMEOUT` and call the same helper for hello
  and auth.
- Any timeout, EOF, stream error, or non-text frame returns `None`; `handle_peer`
  logs phase plus remote address (never frame contents), drops the socket, and
  never registers the peer.
- Keep invalid-signature close behavior. Do not spawn a timer task: the
  connection owner awaits a cancellation-safe `tokio::time::timeout` directly.

**Acceptance Criteria**:
- [ ] A socket that sends neither hello nor auth is released after its respective
      five-second step deadline.
- [ ] A client that sends hello, receives the challenge, and stalls cannot enter
      `PeerRegistry`.
- [ ] Valid and invalid-signature handshakes retain their current behavior.
- [ ] Timeout tests use paused Tokio time/helper-level control rather than sleeps.

---

### Unit 3: Remove empty subscription reverse keys on every edge-removal path

**Files**: `relay/src/subscriptions.rs`, `relay/src/presence.rs`,
`relay/src/rooms.rs`

**Story**: `gate-security-subscription-empty-target-retention`

```rust
impl SubscriptionIndex {
    pub fn replace(&mut self, subscriber: String, targets: Vec<String>);
    pub fn remove(&mut self, subscriber: &str, targets: Vec<String>);
    pub fn remove_all(&mut self, subscriber: &str);

    fn remove_reverse_edge(&mut self, target: &str, subscriber: &str);

    #[cfg(test)]
    fn retained_target_count(&self) -> usize;
}
```

**Implementation Notes**:
- `remove_reverse_edge` removes the subscriber and immediately deletes the
  `subscribers_of[target]` entry when its set becomes empty. Route `remove`,
  `remove_all`, and therefore `replace` through this one cleanup rule.
- Keep `subscriptions_by` absent for empty target sets and preserve dedup via
  `HashSet`.
- No manager API change is needed; presence and rooms continue sharing this
  single index implementation.

**Acceptance Criteria**:
- [ ] Replacing one subscriber through thousands of unique target names retains
      only its current deduplicated targets (maximum 64 from the boundary).
- [ ] Partial remove and disconnect cleanup delete both forward and reverse
      empty entries.
- [ ] Presence and rooms replacement/backfill behavior remains unchanged.

---

### Unit 4: Bound mesh-auth misses and cross-PC authorization work

**Files**: `relay/src/handlers/pi_forward.rs`,
`relay/src/handlers/connection_actor.rs`, `relay/src/mesh/handler.rs`,
`relay/src/lib.rs`, `relay/tests/pi_forward_test.rs`

**Story**: `gate-security-pi-envelope-auth-scan-rate-limit`

```rust
enum CachedMembership {
    Found(std::collections::HashSet<String>),
    Absent,
}

struct CacheEntry {
    membership: CachedMembership,
    cached_at: std::time::Instant,
}

struct MeshAuthCacheInner {
    generation: u64,
    entries: std::collections::HashMap<String, CacheEntry>,
}

impl MeshAuthCache {
    pub fn new() -> Self;
    pub fn is_authorized(&self, pi_a: &str, pi_b: &str, store: &MeshStore) -> bool;
    pub fn invalidate_all(&self);
}

impl ConnectionActor {
    fn allow_pi_forward(&mut self) -> bool;
}

pub async fn post_mesh(
    axum::extract::State(state): axum::extract::State<crate::AppState>,
    axum::extract::Path(url_hash): axum::extract::Path<String>,
    body: axum::body::Bytes,
) -> Result<(axum::http::StatusCode, axum::Json<MeshPostResponse>), MeshHttpError>;
```

**Implementation Notes**:
- Charge one `pi_envelope` attempt before calling `handle_pi_envelope`; exceeding
  256 attempts in the current 60-second window returns `ActorDispatch::Close`
  without an amplification reply. Malformed frames retain boundary handling;
  only typed forwarding reaches the expensive membership lookup.
- Cache a verified miss as `Absent`. Before every insertion, purge expired
  entries; at capacity evict the oldest entry. The 1,024 bound applies to both
  positive and negative entries so attacker-selected authenticated keys cannot
  turn mitigation into another leak.
- `members_of` snapshots the cache generation before scanning. If generation
  changes before insertion, repeat the lookup rather than publishing stale
  results.
- On successful `MeshStore::upsert`, `post_mesh` calls
  `state.mesh_auth.invalidate_all()`. Failed/stale publishes do not invalidate.
  Whole-cache invalidation preserves timely add/revoke behavior without a
  handwritten owner/member reverse index.
- SQLite/blob verification remains fail-closed and payload-private; no raw blob,
  signature, or full peer key is logged.

**Acceptance Criteria**:
- [ ] Repeated authorization for an absent source performs one store scan per
      cache TTL/generation, not one scan per frame.
- [ ] Cache entry count never exceeds 1,024 and expired entries are removable.
- [ ] A successful mesh publish invalidates positive and negative results; a
      racing lookup cannot reinsert the prior generation.
- [ ] The 257th cross-PC attempt in one window closes only that authenticated
      connection; a fresh window accepts again.
- [ ] Authorized, cross-owner, offline, room-targeted, and opaque-envelope
      behavior remains covered.

---

### Unit 5: Replace unbounded outbound channels with bounded drop-newest mailboxes

**Files**: `relay/src/peers/connections.rs`,
`relay/src/peers/registry.rs`, `relay/src/peers/registry_event_publisher.rs`,
`relay/src/handlers/peer.rs`, `relay/src/handlers/connection_actor.rs`,
`relay/src/handlers/control.rs`, `relay/src/handlers/pi_forward.rs`,
`relay/src/metrics.rs`, and relay unit/integration test helpers that register
connections

**Story**: `gate-security-unbounded-outbound-queues`

```rust
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub(crate) struct DeliveryReport {
    pub delivered: usize,
    pub saturated: usize,
}

impl DeliveryReport {
    pub(crate) fn accepted(self) -> bool;
}

pub(crate) struct ConnectionEntry {
    pub conn_id: u64,
    pub device_id: String,
    pub tx: tokio::sync::mpsc::Sender<axum::extract::ws::Message>,
}

impl ConnectionRegistry {
    pub(crate) fn send_to_room(
        &self,
        dest_peer: &str,
        dest_room: &str,
        msg: axum::extract::ws::Message,
        skip_conn_id: u64,
    ) -> DeliveryReport;

    pub(crate) fn send_to_peer(
        &self,
        peer_id: &str,
        msg: axum::extract::ws::Message,
    ) -> DeliveryReport;
}

impl FirehoseMetrics {
    pub fn inc_outbound_queue_dropped(&self, n: u64);
}
```

**Implementation Notes**:
- `handle_peer` creates `mpsc::channel(OUTBOUND_QUEUE_CAPACITY)`; receiver
  ownership and same-device supersession teardown stay with the socket task.
- Delivery clones only for selected recipients and uses `try_send` while the
  short registry lock is held. `Full` drops the returned newest message and
  increments `saturated`; `Closed` is not accepted and is cleaned by normal
  unregister lifecycle. Never await under the `std::sync::Mutex`.
- Count saturation through the existing periodic aggregate metrics reporter;
  do not emit one warning per dropped message (which would create a log DoS).
- `dispatch_outer` remains silent on no accepted destination. Cross-PC delivery
  returns `Forwarded` when at least one matching device mailbox accepted the
  frame; when none accepted, preserve the existing correlated `offline` error.
  Multi-device fanout may therefore deliver to healthy devices while dropping
  only saturated device queues.
- Update the stale Rust relay reference/comment that currently describes
  unbounded send semantics: `.agents/skills/rust-relay/SKILL.md` and
  `relay/src/peers/registry_event_publisher.rs` must state the bounded
  drop-newest contract. This is a code-first rolling-foundation update.

**Acceptance Criteria**:
- [ ] Every live connection mailbox has exactly 16 queued-frame slots; no
      production `UnboundedSender`/`unbounded_channel` remains in relay delivery.
- [ ] Filling a deterministic capacity-one test mailbox drops the next frame,
      reports saturation, and retains the already queued frame.
- [ ] Multi-device delivery succeeds for healthy recipients even if one
      recipient is saturated.
- [ ] Same-device reconnect still closes the prior receiver, and final
      unregister still emits correct room/presence transitions.
- [ ] Aggregate metrics report queue drops without logging message contents or
      producing one log line per drop.

## Implementation Order

1. Unit 1 centralizes policy and limiter arithmetic without behavior change.
2. Unit 3 fixes the isolated retained subscription graph and proves churn
   convergence (`gate-security-subscription-empty-target-retention`).
3. Unit 2 applies the shared handshake deadline
   (`gate-security-auth-challenge-no-timeout`).
4. Unit 5 migrates the shared connection-delivery seam and its test helpers
   (`gate-security-unbounded-outbound-queues`).
5. Unit 4 adds generation-safe mesh negative caching and actor admission after
   the actor/delivery test fixtures use the final bounded mailbox shape
   (`gate-security-pi-envelope-auth-scan-rate-limit`).
6. Run focused tests, then the relay verification commands during implementation;
   child checkpoints advance directly to done on green evidence, followed by
   one standard feature review pass.

## Child checkpoints

The four existing child stories are confirmed and collectively cover every
implementation unit; no additional children are created:

- `gate-security-subscription-empty-target-retention` — `depends_on: []`
- `gate-security-auth-challenge-no-timeout` — `depends_on: []`
- `gate-security-unbounded-outbound-queues` — `depends_on: []`
- `gate-security-pi-envelope-auth-scan-rate-limit` — `depends_on: []`

Their empty dependency arrays are retained because the security behaviors are
logically independent. The order above is a one-owner implementation sequence
chosen to reduce fixture churn, not a semantic dependency and not a reason to
manufacture graph edges. The delegated design write scope intentionally leaves
these pre-existing story files unchanged; this feature body is their coordinated
design authority.

## Simplification

- Replace hello-only timeout and control-only limiter arithmetic with one
  handshake policy and one reusable fixed-window primitive.
- Reuse one `SubscriptionIndex` cleanup rule for presence and rooms instead of
  adding manager-specific sweeps or periodic GC.
- Keep signed mesh blobs authoritative; reject a normalized membership table,
  cache reverse index, background eviction task, and global IP governor for this
  slice.
- Replace boolean delivery ambiguity with a small report used consistently by
  outer, cross-PC, and subscription fanout paths.
- Do not add a new overload wire variant, persistence, retry queue, dependency,
  or operator configuration surface.

## Testing

- **Interface tests**: `relay/tests/integration.rs` protects valid auth, invalid
  auth, and stalled-auth socket release; `relay/tests/pi_forward_test.rs`
  protects authorized/cross-owner/offline/room-targeted behavior after cache and
  limiter changes.
- **Complex-unit tests**: paused-time tests protect fixed-window rollover;
  `pi_forward.rs` tests use a scan-counting test seam or cache introspection to
  prove negative-hit suppression, capacity, generation invalidation, and racing
  publish behavior; `connections.rs` tests use capacity one for deterministic
  saturation.
- **Regression tests**: subscription churn asserts retained target-map size, not
  merely an empty `subscribers_of` result; bounded-mailbox tests assert retained
  first message and dropped newest; same-device reconnect tests protect channel
  teardown and presence/room convergence.
- **Test updates**: migrate current unbounded-channel fixtures to bounded test
  helpers. Do not keep duplicate unbounded fixtures as a compatibility path.
- **Verification deferred to implementation** (design-phase VM restraint): from
  `relay/`, run `cargo fmt --check`, `cargo clippy -- -D warnings`, focused test
  targets, then `cargo test` and `cargo build` when resources permit.

## Risks

- **Riskiest assumption**: a 16-frame mailbox is enough burst tolerance for
  normal chunk streaming while still placing a meaningful memory ceiling.
  Focused integration tests cannot prove production network pacing; saturation
  metrics are the operational signal. Raising the compile-time capacity is the
  reversible fallback and does not change APIs or wire format.
- **Authorization freshness race**: clearing a simple map is insufficient when
  a concurrent SQLite scan can insert after publish. The cache generation/retry
  rule is mandatory; omitting it can preserve revoked membership for the TTL.
- **Queue semantic pressure**: drop-newest can lose transient stream/control
  deltas. Existing reconnect snapshots/history are the convergence mechanism;
  do not add relay replay/offline queues as a fallback because that contradicts
  the product contract.
- **Limiter tuning**: 256 cross-PC envelopes/minute is intentionally generous
  for structured agent messaging but not bulk transport. If real traffic hits
  it, tune the single policy constant from metrics rather than bypassing the
  limiter.
- **Fallback if cache work proves unsafe**: retain the per-connection forward
  limiter and cache capacity, but shorten negative TTL; do not revert to
  unbounded scans. A normalized index is a separate architecture feature, not
  an in-cycle escape hatch.

## Implementation

- Execution capability: `openai-codex/gpt-5.6-sol` (caller-selected for the security-critical relay bundle).
- Review weight: `standard` (caller-selected); advanced to review-ready for one independent feature pass.
- Completed checkpoints: handshake step deadlines, subscription reverse-key cleanup, bounded outbound mailboxes, and bounded mesh-authorization work are all `stage: done`.
- Resource policy: `FixedWindowBudget` now serves control checks and the per-connection 256/minute `pi_envelope` admission path; the previously dead scaffolding is fully wired and clippy-clean.
- Authorization: positive and negative membership results share a 1,024-entry, 60-second cache; successful mesh publishes invalidate it, and generation checks prevent racing scans from restoring stale results.
- Delivery: each live socket owns a 16-frame bounded mailbox. Registry fanout uses `try_send`, drops newest only at saturated recipients, reports aggregate drops, and preserves healthy multi-device delivery and existing `offline` behavior when no mailbox accepts.
- Simplification: no global/IP retained-state governor, cleanup task, persistence change, retry queue, or new wire variant was introduced.
- Discrepancies from design: the durable Rust reference update is outside this worker's allowed write scope; source comments now state the bounded contract. Test-only mailbox fixtures use a centralized bounded compatibility helper while production contains no unbounded sender/channel.
- Verification: from `relay/`, `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` passed; 141 unit tests and every integration target passed. Two pre-existing test-only `unused_mut` warnings remain outside authoritative clippy scope.
- Adjacent issues parked: none.

## Other agent review

- Invoked because: security-critical relay design changes authentication,
  authorization work, retained state, and data-plane backpressure.
- Phase 1 — advisory/completeness: degraded; this delegated worker context did
  not expose a generic subagent/reviewer adapter, so no independent design pass
  could be dispatched with the caller-selected `openai-codex/gpt-5.6-sol`.
- Fixed/active blockers: none found in direct source grounding; generation-safe
  invalidation and bounded negative-cache capacity were added to the design to
  prevent the mitigations themselves from retaining stale/unbounded state.
- Parked: none.
- Rejected: global per-IP admission control in this slice because NAT fairness,
  eviction, and retained-state complexity are not required to close the four
  verified findings.
- Skipped/degraded: design advisory is non-blocking per Part IV. Effective
  implementation/final review weight remains `standard` (caller default): one
  independent feature pass after verification, then receiver adjudication and
  fixes for material current-cycle blockers without re-review.

## Review fixes (standard, 2026-07-19)

The single standard-weight cross-model feature pass returned four material
findings. All were receiver-confirmed, fixed, and verified without a second
review pass, per the standard closure policy.

- **Cross-connection mesh-auth scans:** `MeshAuthCache` now admits one cold scan
  per Pi key process-wide and makes same-key waiters reuse the published result.
  Successful mesh publishes invalidate only newly affected member keys and
  cached membership owned by the publishing Owner; generation checks still
  force racing scans to retry. Scan counters cover same-key concurrency,
  capacity-eviction churn, publish races, and unrelated-owner cache retention.
- **Saturation classification and logs:** `DeliveryReport::accepted()` now
  distinguishes an existing-but-saturated destination from absence. Outer
  dispatch therefore emits the `dest not found` warning only for a true
  zero-delivered/zero-saturated miss; saturation remains observable through the
  aggregate outbound-drop metric without per-frame warning amplification.
- **Loss-aware bounded delivery:** drop-newest remains the bounded mailbox
  policy, but any saturated recipient now receives an idempotent disconnect
  signal. The socket owner unregisters normally, and reconnect hydration
  restores authoritative state instead of allowing a dropped `working:false`,
  `room_ended`, or newer transcript frame to leave a live client divergent. A
  regression test fills a subscriber mailbox, drops `working:false`, and proves
  disconnect recovery is requested while the older queued frame is retained.
- **Current-state relay reference:** `.agents/skills/rust-relay/SKILL.md` now
  records five-second deadlines for both handshake receives, 16-frame bounded
  drop-newest mailboxes with aggregate saturation metrics and disconnect
  recovery, and the bounded positive/negative single-flight mesh-auth cache.
- **Warning cleanup:** removed the review-noted test-only `unused_mut` in
  `handlers/control.rs` and the remaining integration-test `unused_mut`, leaving
  `cargo test` warning-clean.

Verification from `relay/`: `cargo fmt --check`,
`cargo clippy -- -D warnings`, and `cargo test` all passed. The suite reports
147 unit tests and 59 integration tests passing (206 total), with no failures,
ignored tests, or warnings. The feature advances `review → done`; no additional
review pass ran because the effective weight is `standard`.
