---
id: feature-retire-legacy-piext-composition-seams
kind: feature
stage: implementing
tags: [pi-extension, refactor, cleanup]
parent: null
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-15
updated: 2026-07-17
---

# Retire transitional Pi-extension composition/test seams after module extraction

## Brief

The `epic-bold-split-pi-extension-index-*` arc extracted the monolithic
`src/index.ts` into composition-root modules (relay-transport, owner-multiplexer,
cli-daemon-pairing, sdk-session-projection). Several transitional compatibility
seams were left in place to keep the build green during the split; they are now
the canonical wiring and the legacy surfaces are redundant. This feature removes
or neutralizes the transitional shims:

- Migrate legacy index test aliases to the named harness
  (`gate-cruft-index-legacy-test-aliases`)
- Retire or neutralize the legacy index ports adapter after module extraction
  (`gate-cruft-legacy-index-ports-adapter`)
- Retire the temporary relay owner-channel bridge
  (`gate-cruft-relay-owner-channel-bridge`)
- Remove the unused standalone CLI command-surface dependency
  (`gate-cruft-standalone-cli-unused-command-surface`)

## Simplification opportunity

This is the cleanup that closes the module-extraction arc: delete compatibility
adapters, dead test aliases, and the temporary owner-channel bridge once the
split modules are the sole runtime wiring. Pure structural removal — no
observable behavior change to the public surface.

## Source

Promoted from backlog by `scope` (2026-07-15). Cluster of 4 `gate-cruft-*`
findings from the v0.6.0 release `gate-cruft` pass.

## Refactor Overview

All four findings remain present (refactor-design pass 2026-07-16); several
cited line numbers and the old `remotePiTestHarness` name are stale — the
canonical named test seam is now `outpostPiTestHarness` (`index.ts:2714`).
Four cohesive cleanup steps, each mapping to one existing child story.

## Refactor Steps

### Step 1: Make the named test harness the sole test seam
**Priority:** Medium | **Risk:** Medium | **Source Lens:** elimination / dead weight
**Files:** `pi-extension/src/index.ts`, `pi-extension/src/extension.test.ts`, `pi-extension/test/ping.test.ts`
**Story:** `gate-cruft-index-legacy-test-aliases`

**Current State:** `index.ts:2714-2719` exports `outpostPiTestHarness`; `2721-2726` re-exports the same ops under four legacy aliases (`_connectForTest`, `_stopForTest`, `_getState`, `routeClientMessage`). `extension.test.ts:152-169` imports the named harness + three aliases; `ping.test.ts:79-85` imports `_getState`, `_stopForTest`, `routeClientMessage`.

**Target State:** `outpostPiTestHarness` is the single test-facing export. Both test files call `outpostPiTestHarness.connect/.stop/.state()/.routeClientMessage(...)`. The four alias declarations + compat comment removed.

**Implementation Notes:**
- Mechanical migration before removing exports; don't change test setup, timing, assertions, routing.
- Preserve `_routeClientMessageFrom` in `extension.test.ts` (distinct sender-aware seam, not part of this finding).
- In `ping.test.ts`, retain `_startRelayForTest`; only the three named-harness aliases move.

**Acceptance Criteria:**
- [ ] `corepack pnpm typecheck` passes (writable `COREPACK_HOME` + `--store-dir` on this VM).
- [ ] `corepack pnpm test` passes.
- [ ] `corepack pnpm exec vitest run src/extension.test.ts test/ping.test.ts` passes.
- [ ] No source test imports/invokes `_connectForTest`, `_stopForTest`, `_getState`, or the `routeClientMessage` alias.
- [ ] `outpostPiTestHarness` exported unchanged; `_routeClientMessageFrom` + unrelated test seams intact.

**Rollback:** Restore the four direct aliases and revert the two test-file call-site migrations.

### Step 2: Remove the speculative standalone-CLI command-surface dependency
**Priority:** Medium | **Risk:** Low | **Source Lens:** elimination / pattern drift / dead weight
**Files:** `pi-extension/src/extension/command_surface/standalone_cli.ts`, `pi-extension/src/index.ts`, `pi-extension/src/extension/testing.ts`, `pi-extension/src/extension.test.ts`
**Story:** `gate-cruft-standalone-cli-unused-command-surface`

**Current State:** `StandaloneCliAdapterDeps.commandSurface` declared at `standalone_cli.ts:41-43`; `createStandaloneCliDeps` suppresses with `void input.commandSurface` + speculative comment (`:56-60`). `index.ts:2935-2937` supplies `commandSurfaceHarness` (constructed `:922-929`); its interface/factory at `testing.ts:47-59` have no consumer. Actual CLI behavior is `StandaloneCliDeps` + `runStandaloneOutpostPiCli` (`extension.test.ts:370-419`).

**Target State:** `StandaloneCliAdapterDeps` contains only consumed deps. Remove `commandSurface` field, type import, `void` suppression, speculative comment. `index.ts:2935` no longer passes `commandSurface`. Remove `commandSurfaceHarness`, `OutpostPiCommandSurfaceHarness`, `createOutpostPiCommandSurfaceHarness` + unused imports. `runStandaloneOutpostPiCli` + all CLI commands/output unchanged.

**Implementation Notes:**
- Don't route CLI commands through the test harness to make the dep "real" — that adds coupling without product value.
- Preserve the thin command-adapter pattern (explicit storage, daemon, cron, service, probe, launch, supervisor deps).
- No replacement test needed for deleting an unused parameter.

**Acceptance Criteria:**
- [ ] `corepack pnpm typecheck` + `corepack pnpm test` pass.
- [ ] Standalone dispatcher tests `extension.test.ts:370-419` pass without fixture weakening.
- [ ] No `commandSurface` member / unused-value suppression; no `commandSurfaceHarness`/`OutpostPiCommandSurfaceHarness`/`createOutpostPiCommandSurfaceHarness` symbol remains.
- [ ] CLI help text, output, exit behavior, routing byte-for-byte unchanged.

**Rollback:** Restore the deleted harness type/factory/object and pass it back into `createStandaloneCliDeps`.

### Step 3: Replace the legacy ports adapter with the canonical runtime graph
**Priority:** High | **Risk:** Medium | **Source Lens:** elimination / code smell / pattern drift
**Files:** `pi-extension/src/index.ts`, `pi-extension/src/extension/ports.ts`, `pi-extension/src/extension/legacy_ports.ts`, `pi-extension/src/extension/composition_root.ts`, `pi-extension/src/extension/composition_root.test.ts`, `pi-extension/src/extension.test.ts`
**Story:** `gate-cruft-legacy-index-ports-adapter`

**Current State:** `legacy_ports.ts:21-70` re-declares four `Legacy*Deps` interfaces parallel to canonical `ports.ts`. `createLegacyIndexPorts` (`:74-80`) wraps them into `OutpostPiRuntimePorts`; wrapper funcs (`:83-130`) mostly forward unchanged. `LegacyRelayTransportDeps.relay`/`setRelay` (`:29-30`, supplied `index.ts:1619-1620`) not copied into canonical relay port. `SdkSessionProjectionPort.setRoomId` required at `ports.ts:122-126` has no composition-root caller; legacy adapter manufactures a no-op wrapper (`:108`). `index.ts:90` imports adapter; `:1244-1245` constructs `legacyPorts`/`legacyRuntime`; `:1594-1707` builds `LegacyIndexDeps`. `createLegacyCommandSurface` at `:1709`.

**Target State:** `index.ts` defines `createRuntimePorts(): OutpostPiRuntimePorts`; factory passes it directly to `createOutpostPiExtensionRuntime`; names become `runtimePorts`/`runtime`. Each direct port retains the same delegate functions + lifecycle ordering. Remove unused `setRoomId` member (direct `_sdkSessionProjection.setRoomId(...)` calls at `index.ts:416,1979` remain). Rename `createLegacyCommandSurface` → `createRuntimeCommandSurface`. Delete `legacy_ports.ts` + all `Legacy*` imports/types.

**Implementation Notes:**
- Preserve exact composition-root lifecycle sequence `composition_root.ts:98-125` (bind API/context → optional startup → on shutdown: mark epoch disposed, prepare commands, clear contexts, detach bridge, stop relay, close mesh).
- Preserve optional command/session hooks as optional; don't turn absence into throw.
- Don't move large command/session bodies — this is adapter-layer deletion, not module extraction.
- Keep `OutpostPiRuntimePorts` in `ports.ts` as the sole graph contract.
- Remove dead `relay`/`setRelay` deps rather than carrying them into the direct graph.

**Acceptance Criteria:**
- [ ] `corepack pnpm typecheck` + `corepack pnpm test` pass.
- [ ] `corepack pnpm exec vitest run src/extension/composition_root.test.ts src/extension.test.ts` passes.
- [ ] `corepack pnpm build` passes; `dist/` uncommitted.
- [ ] `legacy_ports.ts` deleted; no `LegacyIndexDeps`/`createLegacyIndexPorts`/`legacyPorts`/`legacyRuntime`/`createLegacyCommandSurface` symbol remains.
- [ ] `createOutpostPiExtensionRuntime` receives an `OutpostPiRuntimePorts`-satisfying object.
- [ ] Session-start/shutdown ordering + command registration assertions unchanged.

**Rollback:** Restore `legacy_ports.ts`, `createIndexDeps(): LegacyIndexDeps`, wrap with `createLegacyIndexPorts` before constructing runtime.

### Step 4: Close the relay owner-channel escape hatch
**Priority:** High | **Risk:** High | **Source Lens:** missing abstraction / pattern drift / dead weight
**Files:** `pi-extension/src/index.ts`, `pi-extension/src/extension/ports.ts`, `pi-extension/src/extension/relay_transport.ts`, `pi-extension/src/extension/relay_transport.test.ts`, `pi-extension/src/extension/owner_multiplexer.ts`, `pi-extension/src/extension/owner_multiplexer.test.ts`, `pi-extension/src/extension/command_surface/pairing_coordinator.ts`, `pi-extension/src/extension.test.ts`
**Story:** `gate-cruft-relay-owner-channel-bridge`

**Current State:** `RelayTransportAdapter.currentRelayForOwnerChannels()` marked temporary (`relay_transport.ts:63-68`), returns live socket (`:470`). `index.ts` reaches through it for: owner ingress (`:355-358`), post-await relay re-check (`:363-366`), direct `subscribe_presence` (`:378-382`), relay availability to `PairingCoordinator` (`:408-412`). `AttachOwnerInput` exposes concrete `RelayClient` (`ports.ts:89-96`); `OwnerOuterLineInput` same (`owner_multiplexer.ts:110-119`). `RelayTransportPort.createPeerChannel` optional (`ports.ts:77-85`), concrete adapter always implements (`relay_transport.ts:349-357`). `PairingCoordinator.startRelay` has dead concrete-`RelayClient` impl (`pairing_coordinator.ts:186-293`) bypassed by `index.ts:463` overwrite with `_startRelayViaTransport`. `index.ts:1873-1879` casts `PairingCoordinator` to private internals.

**Target State:** `RelayTransportPort` owns all live-relay ops (required owner-channel creation, outer-message subscription, presence subscription, relay connectivity/status). Outer-message callbacks receive an opaque `isCurrent()` predicate captured per connection-generation; transport invalidates on unbind/close/stop/replacement/reconnect (preserves the post-`await` stale-relay guard without exposing `RelayClient`). `OwnerMultiplexer` no longer imports/accepts `RelayClient` (remove `relay` from `AttachOwnerInput` + `OwnerOuterLineInput`; attach/reconnect via injected channel factory). `_handleOwnerOuterLine` passes the freshness predicate into the multiplexer. `_syncOwnerPresenceSubscription` calls a narrow relay-port method emitting the existing `{ type: "subscribe_presence", peers }` frame unchanged. `PairingCoordinatorDeps` receives injected `startRelay` + `isRelayConnected`/status ops; `PairingCoordinator.startRelay` delegates instead of being overwritten. Remove the dead concrete-relay start/listener/pairing impl + duplicate decoders/send helper. Replace the `index.ts` private cast with explicit coordinator operations (record current keypair, start self-revoke). Delete `currentRelayForOwnerChannels()`.

**Implementation Notes:**
- Preserve ingress invariants: one outer-message listener per current relay; known-owner reconnect attaches once + routes triggering message once; unknown owners get one sender-only `unknown_peer` response; pairing success/error shapes unchanged; stale async ingress can't attach after relay replacement; reconnect detaches old owner channels + permits known-owner reattachment.
- Preserve `relay_transport.test.ts:112-129`: raw control-frame lines reach outer-message handlers + decoded control handlers.
- Preserve `subscribe_presence` wire frame exactly; only its ownership moves.
- Use transport status for pairing/revoke availability; `reconnecting` stays unavailable (matches current `relay === null`).
- Don't change `RelayClient`, `PlainPeerChannel`, protocol envelopes, room routing, reconnect backoff, or user-visible messages.
- Add/update a focused transport test proving a callback's `isCurrent()` becomes false after close/replacement (protects the current `index.ts:366` concrete-relay-identity comparison).
- Keep this step atomic: partial removal can create duplicate listeners or stale-owner attachment.

**Acceptance Criteria:**
- [ ] `corepack pnpm typecheck` + `corepack pnpm test` pass.
- [ ] `corepack pnpm exec vitest run src/extension/relay_transport.test.ts src/extension/owner_multiplexer.test.ts src/extension.test.ts` passes.
- [ ] `corepack pnpm build` passes; `dist/` uncommitted.
- [ ] No `currentRelayForOwnerChannels` symbol / direct live-relay accessor remains.
- [ ] `owner_multiplexer.ts` + `pairing_coordinator.ts` no longer import/accept `RelayClient` for owner ingress.
- [ ] No `_pairingCoordinator.startRelay = ...` runtime reassignment or private-internals cast remains.
- [ ] Tests prove one-listener/single-delivery, stale-ingress rejection, known-owner reconnect, unknown-owner response, pairing, presence subscription, reconnect reattachment.
- [ ] Protocol frames, CLI output, lifecycle timing, persisted data unchanged.

**Rollback:** Revert as one unit — restore `currentRelayForOwnerChannels`, concrete-relay freshness comparison, direct presence send, previous coordinator wiring. No mixed state.

## Implementation Order

1. `gate-cruft-index-legacy-test-aliases` — migrate tests + remove redundant aliases.
2. `gate-cruft-standalone-cli-unused-command-surface` — remove speculative CLI dep + dead command harness.
3. `gate-cruft-legacy-index-ports-adapter` — establish direct canonical port graph + delete `legacy_ports.ts`.
4. `gate-cruft-relay-owner-channel-bridge` — remove the concrete relay escape hatch after the canonical graph is the sole composition boundary.

Steps are sequential (every step touches `index.ts`; step 4 has historically sensitive listener/reconnect behavior). Each step committable in isolation. The 4 existing child stories map 1:1 to these steps — no new child stories needed.
