# Reachability contract

This is the interim canonical source for Outpost-Pi reachability until `epic-bold-generated-protocol` absorbs it into the generated protocol schema. It lives under `protocol/schema/` because `.orchestration/` is retired except for legacy contract fixtures.

Language projections must derive states, display names, backoff values, heartbeat timings, and transition names from `protocol/schema/reachability.json`. They must not invent additional states or drift the `[1, 2, 5, 10, 30]` backoff policy. Bounded stack-local retry exceptions for locally-classified failure kinds are permitted (the app's zero-inbound handshake-stall fast cycle) as long as the canonical ladder remains the policy for ordinary failures and the schema itself is unchanged.

`degraded` means the transport is still up but the app/Pi room liveness signal is stale. It is not a relay-wide disconnect and does not imply offline queueing.
