# Pattern: Centralized Resource Policy

## Rationale

The relay has several independent attacker-controlled resource owners: a WebSocket connection mailbox, per-connection admission budgets, and the mesh-auth cache. Keep their ceilings, windows, and shared fixed-window accounting in `resource_limits.rs`, then make the owner import the policy. This keeps an operational limit and its enforcement/test coverage from silently drifting apart.

## When to use

Use this when a relay resource owner needs a bounded queue, cache, request budget, handshake deadline, or similar finite resource policy.

- Define the ceiling/window and shared accounting primitive in `resource_limits.rs`.
- Keep stateful enforcement with the owning connection or cache.
- Exercise the same named limit in its boundary tests.

## When not to use

Do not move protocol-schema limits or a one-off local algorithm invariant into this module. Schema-derived wire limits remain in the generated protocol contract, and purely local implementation details should remain local.

## Examples

### Example 1: Authenticated connection mailbox

**File:** `relay/src/resource_limits.rs:10`

```rust
/// Number of frames retained for one authenticated connection's outbound mailbox.
pub const OUTBOUND_QUEUE_CAPACITY: usize = 16;
```

**File:** `relay/src/handlers/peer.rs:96`

```rust
let (tx, mut rx) = mpsc::channel::<Message>(OUTBOUND_QUEUE_CAPACITY);
```

The socket owner applies the shared mailbox ceiling at the authenticated-connection boundary.

### Example 2: Per-connection fixed-window budgets

**File:** `relay/src/resource_limits.rs:16-24`

```rust
pub const PI_FORWARD_WINDOW: Duration = Duration::from_secs(60);
pub const MAX_PI_FORWARDS_PER_WINDOW: usize = 256;
pub const MAX_CONTROL_FRAME_PEERS: usize = 64;
pub const MAX_CONTROL_CHECK_PEER_COST_PER_WINDOW: usize = MAX_CONTROL_FRAME_PEERS * 4;
pub const CONTROL_CHECK_PEER_COST_WINDOW: Duration = Duration::from_secs(60);
```

**File:** `relay/src/handlers/connection_actor.rs:43-46`

```rust
budget: FixedWindowBudget::new(
    CONTROL_CHECK_PEER_COST_WINDOW,
    MAX_CONTROL_CHECK_PEER_COST_PER_WINDOW,
),
```

**File:** `relay/src/handlers/connection_actor.rs:112-115`

```rust
pi_forward_limiter: FixedWindowBudget::new(
    PI_FORWARD_WINDOW,
    MAX_PI_FORWARDS_PER_WINDOW,
),
```

The connection actor owns mutable budget state while its policy parameters remain centralized.

### Example 3: Bounded mesh-auth cache

**File:** `relay/src/resource_limits.rs:12-14`

```rust
pub const MESH_AUTH_CACHE_CAPACITY: usize = 1_024;
pub const MESH_AUTH_CACHE_TTL: Duration = Duration::from_secs(60);
```

**File:** `relay/src/handlers/pi_forward.rs:165-195`

```rust
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

fn is_fresh(&self, entry: &CacheEntry) -> bool {
    self.now().duration_since(entry.cached_at) < MESH_AUTH_CACHE_TTL
}
```

The cache enforces freshness and named capacity from the same policy module,
then inserts the current membership with a fresh timestamp.

## Common violations

- Copying a queue size, TTL, or request ceiling into a handler or test instead of importing the named policy.
- Making the policy global mutable state when the owner needs per-connection accounting.
- Replacing a bounded owner with an unbounded channel or map without an explicit recovery policy.
