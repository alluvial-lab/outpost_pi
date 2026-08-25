---
id: epic-rebrand-to-outpost-pi-en-first-pi-extension
kind: feature
stage: done
tags: [rebrand, docs, i18n, pi-extension]
parent: epic-rebrand-to-outpost-pi-en-first
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
---

# EN-first + JSDoc gap-fill — pi-extension

## Brief

Translate Portuguese → English and adopt the JSDoc documentation framework
in `pi-extension/`. This is the smallest code slice of the EN-first epic
(6 PT-bearing source files), but it is also the **reference implementation**
of the per-language doc convention: it is the first subproject to run the
full translate + gap-fill pass against
`.agents/skills/documentation-conventions/SKILL.md`, so its design pass
establishes the working pattern (Always-tier export audit → translate
comments → gap-fill missing JSDoc → verify) that the larger Dart slices
inherit by reference.

Covers `pi-extension/src/` only. The 6 PT-bearing files are: `index.ts`,
`mesh/siblings.ts`, `mesh/canonical.ts`, `mesh/canonical.test.ts`,
`session/broker_remote.ts`, `session/cwd_lock.ts`. PT here is comment prose
(no user-facing UI strings — the extension has no UI).

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi-en-first`
- Position in epic: **foundation / reference slice** — smallest, no UI, no
  cross-subproject types. Establishes the translate+gap-fill working pattern.
  Other subproject features inherit the approach by reference, not by a hard
  `depends_on` (the convention is already landed; this feature just proves it
  end-to-end on one language first).

## Foundation references
- `.agents/skills/documentation-conventions/SKILL.md` — the Always/Recommended/
  Skip tier model and JSDoc format for TypeScript. This feature's gap-fill
  scope is the Always tier: exported functions/types/classes from shared/domain
  layers, service-layer functions, `Result`/discriminated-union-returning
  functions.
- `.agents/skills/scan-documentation/SKILL.md` — the gate that will verify
  coverage; run it as a self-check before advancing to review.
- Parent epic `## Grounded surface measurement` — the 6-file count.
- Parent epic `## Design prerequisite (landed 2026-07-14)` — the convention is
  already in place; this feature consumes it, does not re-derive it.

## What this feature does NOT cover
- Wire-stable identifiers (auth string, control-RPC discriminator) — owned by
  the first rebrand epic's wire-stable migration feature, already shipped.
- Product-identity string renames — owned by the mechanical-rename feature.
- `scripts/` shell comments — explicitly out of scope (operator glue; locked
  boundary in the parent epic's parent).
- Generated/vendored state (`node_modules/`, `dist/`).

## Verification
```bash
# from pi-extension/
corepack pnpm typecheck && corepack pnpm test && corepack pnpm build
```
Plus a grep confirming zero PT (accented Latin) in `pi-extension/src/`.

## Design decisions

- **Scope boundary**: Translate only comment/JSDoc/test-description prose and
  add JSDoc; preserve all runtime strings, exported signatures, protocol
  identifiers, serialized values, and generated output — this is a
  behavior-preserving documentation slice.
- **Accented-Latin verification**: Change the non-PT `Renée 🦀` test fixture in
  `mesh/canonical.test.ts` to `Renee 🦀`. The emoji still proves UTF-8 handling,
  while a zero-accented-Latin candidate scan no longer reports a false PT hit.
- **JSDoc scope**: Apply the convention's Always tier, not a blanket
  "document every export" rule. Schema/DTO declarations, barrels, constants,
  generated code, tests, and trivial helpers remain Skip-tier.
- **Dispatch**: Direct-read mapping only. The source set and documentation
  convention were already bounded; exploratory fan-out would duplicate local
  evidence. Implementation splits into three non-overlapping write-owned
  stories for raised-tier parallel dispatch.

## Other agent review

- Not invoked: this is a bounded, behavior-preserving translation and
  documentation pass with no architectural or irreversible decision. Per the
  advisory policy, low-risk design does not need a cross-model pass.

## Architectural choice

### Options considered

1. **Translate only existing prose.** Smallest diff, but leaves the measured
   Always-tier JSDoc deficit and fails the parent epic's native-doc-framework
   objective.
2. **Add JSDoc to every exported declaration.** Maximizes raw coverage but
   violates the convention by producing redundant docs on wire/storage DTOs,
   barrels, constants, generated artifacts, and test seams.
3. **Translate the six detected files and fill only audited Always-tier gaps.**
   Chosen. It consumes the landed convention, preserves code behavior, and
   gives the other language slices a repeatable audit → translate → gap-fill →
   verify pattern.

No new abstraction, protocol contract, or dependency is introduced. Existing
ports, generated protocol output, and lifecycle ownership remain authoritative.

## Implementation Units

### Unit 1: Translate the PT-bearing files

**Files**: `pi-extension/src/index.ts`, `pi-extension/src/mesh/siblings.ts`,
`pi-extension/src/mesh/canonical.ts`,
`pi-extension/src/mesh/canonical.test.ts`,
`pi-extension/src/session/broker_remote.ts`, and
`pi-extension/src/session/cwd_lock.ts`

**Story**: `epic-rebrand-to-outpost-pi-en-first-pi-extension-translate-pt-bearing-files`

```ts
// Signatures and runtime identifiers remain unchanged; only surrounding prose
// changes. Existing contracts keep their public shape.
export function canonicalize(value: unknown): string;
export async function discoverSiblings(opts: DiscoverOptions): Promise<SiblingPi[]>;
export class BrokerRemote implements RemoteRouter { /* unchanged */ }
export async function acquireCwdLock(cwd: string, name?: string): Promise<CwdLockResult>;
```

**Implementation notes**:

- Translate every detected PT comment, including block comments, inline notes,
  and test descriptions. Do not translate protocol frame strings, source paths,
  code identifiers, plan references needed for historical traceability, or
  user-facing runtime strings (none are in this set).
- `canonical.test.ts` is Skip-tier for JSDoc. Change `Renée 🦀` to `Renee 🦀`
  only because it is an accented-Latin scan false positive; retain the emoji so
  the test still covers non-ASCII UTF-8 bytes.
- Add missing Always-tier JSDoc in these files only: `RemoteState` if still
  undocumented; `DiscoverSelfLabelResult`, `DiscoverOptions`,
  `RemotePeerEntry`, `BrokerRemoteOptions`, `BrokerRemote`, `AcquiredLock`,
  `RefusedLock`, and `CwdLockResult`. Do not document underscore-prefixed
  index test seams/harnesses.

**Acceptance criteria**:

- [ ] The six files contain English comment prose and no accented-Latin PT
  candidate.
- [ ] Canonical JSON, broker routing, lock acquisition, and public APIs are
  byte-for-byte behaviorally unchanged apart from the ASCII-only test fixture.
- [ ] Added JSDoc explains mesh/lock contracts without re-stating fields.

---

### Unit 2: JSDoc composition, command, config, and daemon services

**Files**: `pi-extension/src/actions/handlers.ts`, `config.ts`, `daemon/**/*.ts`,
and `extension/**/*.ts` (excluding `extension/testing.ts`)

**Story**: `epic-rebrand-to-outpost-pi-en-first-pi-extension-jsdoc-composition-daemon`

```ts
/** Resolve the configured relay source; callers must handle unconfigured state. */
export function resolveRelayUrl(): RelayResolution;

/** Create a lifecycle-owned extension runtime from injected ports. */
export function createOutpostPiExtensionRuntime(
  pi: ExtensionAPI,
  ports: OutpostPiRuntimePorts,
  coordinator?: OutpostPiRuntimeCoordinator,
): OutpostPiRuntime;
```

**Always-tier gap-fill list**:

- `actions/handlers.ts`: `handleSessionCompact`, `handleSessionNew`,
  `handleThinkingSet`, `handleModelSet`, `handleListModels`.
- `config.ts`: `loadConfig`, `saveConfig`, `ConfiguredRelayResolution`,
  `UnconfiguredRelayResolution`, `RelayResolution`; skip `OutpostPiConfig` as
  a storage shape.
- `daemon/client.ts`: `SupervisorOfflineError`, `callSupervisor`,
  `supervisorOnline`; `daemon/control_protocol.ts`: `encodeRequest`,
  `encodeReply`, `parseReply` (skip request/reply DTOs).
- `daemon/cron_registry.ts`: `CronRegistry`, `saveCronRegistry`, `listJobs`,
  `getJob`, `removeJob`, `setJobEnabled`, `ScheduleValidation`,
  `validateSchedule`, and `nextRunFor`; `daemon/registry.ts`: registry
  load/save/mutation/list/migration operations (skip record DTOs).
- `daemon/rpc_child.ts`: `RpcChild`; `daemon/supervisor.ts`:
  `decideFireAction`, `Supervisor`; `daemon/install.ts`: installation,
  uninstallation, binary-linking result contracts and their non-trivial
  service functions. Skip constants and simple platform/path helpers.
- `extension/command_surface/**/*.ts` and `command_surface.ts`: exported
  command specs/ports, adapter classes, and CLI construction/launch functions.
- `extension/composition_root.ts`: `OutpostPiRuntime`, `createRuntimeEpoch`,
  `createOutpostPiExtensionRuntime`, `registerLifecycleHooks`,
  `createOutpostPiExtensionFactory`; `legacy_ports.ts`: exported injected-port
  contracts and `createLegacyIndexPorts`.
- `extension/owner_multiplexer.ts`: exported channel/owner contracts,
  `decodeOuterEnvelope`, `decodeClientMessage`, `createOwnerMultiplexerPort`;
  `ports.ts`: all exported runtime/transport/session/command port contracts;
  `relay_transport.ts`: exported adapter/result contracts,
  `RelayStartAbortedError`, `decodeRelayControlFrame`,
  `createRelayTransportPort`; `runtime_coordinator.ts`: lifecycle/lease
  contracts and `getOutpostPiRuntimeCoordinator`; `types.ts`:
  `RelayConnectivity`.

**Implementation notes**:

- Explain lifecycle owner, injected dependency, stale-session handling, or
  failure/result meaning when it is not clear from the signature. Use `@throws`
  for APIs that throw rather than return a typed failure.
- Do not add documentation to `extension/testing.ts`, test-only harness exports,
  constants, or config/wire DTOs merely to increase count.

**Acceptance criteria**:

- [ ] Every listed Always-tier export has concise EN JSDoc.
- [ ] Port docs state the behavioral contract and teardown/error ownership, not
  a duplicate of TypeScript property types.
- [ ] No daemon, extension, command, or config behavior changes.

---

### Unit 3: JSDoc mesh, pairing, protocol, session, and transport services

**Files**: `pi-extension/src/mesh/` (except Unit 1), `pairing/`, `protocol/`
(non-generated), `reachability/`, `session/` (except Unit 1), and `transport/`

**Story**: `epic-rebrand-to-outpost-pi-en-first-pi-extension-jsdoc-session-protocol`

```ts
/** Decode and validate an app frame at the protocol boundary. */
export function decodeClient(line: string): ClientMessage;

/** Resolve the current SDK session identity, recovering from stale contexts. */
export function resolveRemoteSessionId(ctx: unknown): RemoteSessionId;

/** Reduce a typed turn event into the next convergence-safe snapshot. */
export function reduceTurn(snapshot: TurnSnapshot, event: TurnEvent): TurnSnapshot;
```

**Always-tier gap-fill list**:

- `mesh/self_revoke.ts`: `SelfRevokeOptions`, `SelfRevoke`; `pairing/crypto.ts`:
  `Ed25519Keypair`, `ed25519Sign`, `ed25519Verify`; `pairing/qr.ts`:
  `qrSession`, `buildQRUri`; `pairing/storage.ts`: `listPeers`, `addPeer`,
  `removePeer` (skip `PeerRecord` storage DTO).
- `protocol/codec.ts`: `DecodeError`, `encodeClient`, `decodeServer`,
  `decodeClient`; `protocol/session_scope.ts`: `RemoteSessionId`, exported
  type predicates, and any missing canonical-registry contract docs. Skip
  generated code and self-evident schema registries.
- `reachability/contract.ts`: `ReachabilityState`, `reachabilityBackoffMs`,
  `ReachabilityTransition`, `ReachabilityEvent`; document the one canonical
  state-machine contract rather than duplicating constant tables.
- `session/bridge.ts`: `CrossPcBridge`, `attachCrossPcBridge`; `broker.ts`:
  `Broker`; `envelope.ts`: `EnvelopeError`, `serialize`, `parse`;
  `leader_election.ts`: `ElectionResult`; `local_config.ts`:
  `loadLocalConfig`, `saveLocalConfig`; `mesh_node.ts`: `MeshNode`.
- `session/peer.ts`: `ReconnectHandler`, `SessionPeerOptions`, `AckStatus`,
  `AckResult`, `SessionPeer`; `remote_session.ts`: `RemoteSession`, `uuid7`,
  `resolveRemoteSessionId`, `RemoteSessionIssuer`; `session_gate.ts`:
  `SessionGateResult`, `validateClientSession`.
- `session/sdk_session_projection.ts`: public API/action/history/output/options
  contracts, `isAgentMessageApi`, and `SdkSessionProjection`.
- `session/transcript_event.ts`, `transcript_projection.ts`, and `turn_state.ts`:
  all exported domain union/projection/reducer contracts and their exported
  mapping/reducer functions; `session/wizard.ts`: `joinWizard`.
- `transport/pi_forward_client.ts`: `PiForwardClient`; audit `relay_client.ts`
  and `peer_channel.ts` for any genuinely missing service/event contract docs.

**Implementation notes**:

- These exports carry cross-PC, session, transcript, and turn-state contracts;
  JSDoc must state validation/error semantics, opaque-data handling, lifecycle
  teardown, or convergence guarantees where relevant.
- Do not document DTO-only mesh/wire/storage declarations, generated protocol
  declarations, test modules, or simple constants.

**Acceptance criteria**:

- [ ] Every named contract-bearing export has EN JSDoc appropriate to its tier.
- [ ] JSDoc does not modify protocol, relay routing, session IDs, or mesh
  membership semantics.
- [ ] Generated code and tests retain the Skip-tier boundary.

## Tricky unit and pre-mortem

The risky part is classification, not translation: a raw export scan reports
roughly 379 undocumented declarations, but documentation on every one would
create redundant noise and violate the convention. The implementation must
re-audit against the explicit lists above and leave Skip-tier declarations
undocumented. The fallback for a disputed export is to keep it Skip-tier unless
it is a shared/domain contract, a service/factory/middleware boundary, or a
Result/discriminated-union API; record any exception in the story body.

## Risks

- **False-positive language scan**: accented non-PT sample data can look like
  PT. Mitigated by the `Renée` → `Renee` fixture decision while retaining emoji
  UTF-8 coverage.
- **Noisy or stale docs**: copying signatures into JSDoc is drift-prone.
  Mitigated by the convention's intent/contract focus and scan-documentation
  self-check.
- **Concurrent edit conflicts**: Units own disjoint file sets. Unit 1 alone
  owns the six PT-bearing files; Units 2 and 3 must not touch them.

## Testing

- **Source audit**: run the required accented-Latin grep over
  `pi-extension/src/`, then inspect every hit; it must produce no candidates
  after Unit 1. Re-run an export/JSDoc audit against the above Always-tier list
  and use `.agents/skills/scan-documentation/SKILL.md` as the self-check.
- **Focused regression tests**: Unit 1 runs canonical/siblings/broker-remote/
  cwd-lock tests; Unit 2 runs relevant daemon/extension tests; Unit 3 runs
  protocol/session/transport tests. Tests assert existing behavior and are not
  rewritten for comment-only work.
- **Feature gate** (from `pi-extension/`):
  `COREPACK_HOME=/tmp/corepack-home corepack pnpm --store-dir /tmp/pnpm-store typecheck && COREPACK_HOME=/tmp/corepack-home corepack pnpm --store-dir /tmp/pnpm-store test && COREPACK_HOME=/tmp/corepack-home corepack pnpm --store-dir /tmp/pnpm-store build`.

## Implementation order

1. Dispatch the three independent stories in parallel with raised-tier workers;
   their write ownership is disjoint.
2. Reconcile the combined source audit, including the zero-candidate PT scan
   and the Always-tier JSDoc audit.
3. Run the full `typecheck`, `test`, and `build` gate, then advance the feature
   to review for a fresh-context review.

## Review (2026-07-15, standard, cross-model fresh-context)

Reviewer: `openai-codex/gpt-5.6-sol` (different model class from the umans
orchestrator). One balanced pass over the integrated feature diff
(`376fa38..HEAD -- pi-extension/src/`).

### Findings (adjudicated)
- **Important — incomplete translation: residual ASCII Portuguese.** The feature's verification used an accented-character scan only, which missed ASCII PT in comments and test descriptions: `Fase` (broker.ts, broker_remote.test.ts, e2e.test.ts), `<nome>` address-format placeholders (broker.ts, local_config.ts, peer.ts, mesh_node.ts, broker_remote.test.ts, local_config.test.ts), `reescrito` (local_config.ts). Translated all to `Phase`/`<name>`/`rewritten` and re-ran a broad ASCII PT-word scan (clean). **Fixed.**
- **Important — `RemoteState` undocumented.** The exported `RemoteState` type (`index.ts:153`) was listed for Always-tier gap-fill but had no JSDoc. Added meaningful JSDoc describing the `idle`/`started` relay runtime lifecycle contract. **Fixed.**
- **Important — feature contract under-scoped a production literal change.** `pairing_coordinator.ts:410` changed a user-visible notification literal (`Use mais chars.` → `Use more characters.`) in commit `27d3fd0` (a Phase 8 review-fixup), but the feature body claimed comments/JSDoc-only with no literal change. The translation itself is correct; the contract description was inaccurate. **Re-scoped:** this feature's translation slice includes the one observable copy change in `pairing_coordinator.ts` (the `mais` → `more` fix), as an exception to the comments-only boundary. All other owned changes remain comments/JSDoc-only.
- No other findings; wire-stable values unchanged (`index.ts:168,170`, `protocol.generated.ts:87`).

### Verification of fixes
- `corepack pnpm typecheck` clean.
- `corepack pnpm test`: 830 passed, 3 skipped, 8 failed — the 8 failures are the documented pre-existing `acquireCwdLock` EROFS environmental flake (read-only `~/.pi/remote/locks/` in this sandbox), unrelated to this doc/comment change.

### Verdict
Approve. Advanced `review → done`.
