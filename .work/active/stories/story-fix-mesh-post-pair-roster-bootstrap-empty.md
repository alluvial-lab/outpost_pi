---
id: story-fix-mesh-post-pair-roster-bootstrap-empty
kind: story
stage: done
tags: [pi-extension, app, bug, testing]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: null
created: 2026-08-22
updated: 2026-08-22
---

# Bootstrap mesh roster when membership arrives during bridge attachment

## Symptom

The live two-Pi device lane paired one Owner to two already-connected Pi hosts,
published signed two-member membership, and refreshed both hosts. Both reported
`bridgeActive=true`, but both remote broker rosters stayed empty for 60 seconds
(`bridgeA=true bridgeB=true peersA=0 peersB=0`). Evidence is retained under
`.work/session-notes/live-mesh-20260822/`.

## Root cause

Three lifecycle gaps composed into the empty roster:

1. `SelfRevoke.onMembersChanged` forwards verified siblings to
   `MeshNode.setSiblings`, but during asynchronous `attachCrossPcBridge`
   discovery `brokerRemote` is null, so the publication was silently dropped.
2. `BrokerRemote.setSiblings` bootstrapped only newly added keys. Re-publishing
   an unchanged signed membership could not repair an earlier `peers_request`
   exchange that raced the remote bridge's readiness.
3. The extension-owned `RelayTransport` decoded room controls into its bounded
   control FIFO and dispatched them only to app/owner control handlers. It did
   not publish the already-decoded `rooms` frame to the typed relay-ingress
   fanout consumed by `PiForwardClient`, so `BrokerRemote._handleRooms` never
   learned a destination room and could not send `peers_request` at all. Direct
   test envelopes still worked because cross-PC frames followed the data-plane
   fanout, which explained the misleading combination of functioning delivery
   and an empty roster.

## Fix approach

- Retain the latest verified sibling publication in `MeshNode`, including while
  no bridge exists, and replay it onto a newly completed current bridge. Null
  means no publication yet, preserving bridge discovery as startup authority.
- Treat every membership publication as a convergence trigger in
  `BrokerRemote`: known rooms receive an immediate `peers_request` plus local
  `peers_update`; unknown rooms receive subscribe/snapshot bootstrap.
- Publish validated server control DTOs from `RelayTransport` to the shared
  typed fanout after owner control handlers, so the attached `PiForwardClient`
  receives `rooms`, `room_announced`, and `room_ended` without a second parse.
- Restore the linked live-device roster test. It requires each host's current
  broker-issued address to appear in the opposite remote roster; exact roster
  cardinality is intentionally outside this fix because a separate live-adapter
  duplicate-local-join oddity is parked.

## Regression tests

- `pi-extension/src/session/mesh_node.test.ts` gates bridge attachment with an
  explicit deferred barrier, publishes siblings while attachment is in flight,
  then requires replay onto the completed bridge. Before the fix: zero calls.
- `pi-extension/src/session/broker_remote.test.ts` models a dropped first roster
  exchange, republishes identical membership, and requires an immediate
  `peers_request` + `peers_update`. Before the fix: zero sends.
- `pi-extension/src/extension/relay_transport.test.ts` injects a validated
  `rooms` control through the extension-owned transport and requires the
  attached `PiForwardClient` to observe it. Before the fix: empty observation.

All three use explicit events/barriers and no real-time sleeps.

## Implementation notes

- **Execution capability:** `sol/high`, selected because the focused defect
  crossed asynchronous bridge attachment, signed-membership convergence, and
  the extension's decode-once relay fanout while remaining one pi-extension
  lifecycle repair.
- **Files changed:** `pi-extension/src/session/mesh_node.ts`,
  `pi-extension/src/session/broker_remote.ts`,
  `pi-extension/src/extension/relay_transport.ts`, their regression tests,
  `app/integration_test/live_mesh_test.dart`, this story, and the now-empty
  expected-soak manifest. The backlog source was promoted/removed.
- **Failing reproduction:** all three deterministic tests failed before their
  corresponding fix; the pre-fix live device run again timed out at 60 seconds.
- **Four-step confirmation:** targeted regressions pass; full extension
  typecheck/test/build pass; the original two-Pi-host device scenario passes
  both test cases; the live output reports all three cross-Pi fault scenario
  checkpoints plus the restored mutual-roster test.
- **Nightly manifest:** removed
  `backlog-mesh-post-pair-roster-bootstrap-empty`; the manifest is zero bytes
  because both known findings are now closed.
- **Adjacent issue parked:** `idea-pi-host-double-mesh-join-ghost` tracks the
  live adapter's duplicate base/`#2` local entries. The roster assertion checks
  current counterpart presence without hiding that separate defect.

## Verification

- Targeted regressions: PASS, 66/66 across relay transport, mesh node, and
  broker remote suites.
- `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`: PASS;
  999 tests passed, 3 pre-existing skips.
- `flutter analyze`: PASS, no issues.
- `E2E_LIVE_TIMEOUT_SECONDS=900 e2e/run-live.sh mesh`: PASS on the exclusive
  emulator lane; 2/2 live tests passed, including post-pair mutual roster.
- The earlier full Flutter unit-suite verification exposed unrelated
  load-sensitive `sync_service_test.dart` drift, separately parked as
  `idea-app-sync-service-suite-flakes`; this fix changes no app runtime code.

## Bounded inline review

**Verdict: PASS.** Reviewed the complete diff against signed-membership
boundary rules, decode-once fanout ownership, bridge generation fencing,
anti-spoof membership authority, and teardown. Retained membership is copied,
replayed only onto a current completed bridge, and does not overwrite discovery
before any verified publication. Control frames remain one decoded FIFO item and
are published exactly once. Membership refresh performs bounded idempotent
bootstrap without changing wire shapes. The live assertion proves counterpart
presence while keeping the duplicate-local-join defect visible in its own item.
No material blocker or unrelated production change remains. Per standalone-story
policy, this was an inline self-review with no independent or cross-model
reviewer.
