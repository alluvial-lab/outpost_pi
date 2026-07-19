---
id: feature-cross-component-e2e-pairing-suite
kind: feature
stage: implementing
tags: [testing, e2e-test]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-02
updated: 2026-07-18
---

# Cross-component e2e suite for the pairing → session-hydrate lifecycle

## Brief

Remote Pi shipped `v0.6.0` green-on-paper and non-functional: the `/remote-pi pair`
flow was broken by three sequential integration/lifecycle bugs (QR not rendering,
cross-room `pair_request` dropped, post-pair frames rejected for missing `room`).
Every one of them passed the unit suite because the unit tests used unrealistic
mock envelope shapes and lifecycle contexts — `session_start` ctx carrying
`sendMessage`, outer envelopes with no `room` field, inbound rooms always matching
the recipient's. The relay's `integration.rs` tests the relay alone; there is no
test that starts the relay + the pi extension + an app client together and
asserts the chronological lifecycle actually completes end to end.

This feature introduces a cross-component e2e harness that models the real
chronological steps an operator/user performs — start the relay, start the pi
session, pair a device, hydrate the session — and asserts each state transition
actually occurs across the wire. The goal is that the three bugs fixed this
session would each have failed a case in this suite.

Narrow first: this feature targets the **pairing arc** (relay up → pi session up
→ app pair → `pair_ok` → session transcript hydrates). The broader cross-component
program (reconnect, session-replacement `/new`/`/fork`, cross-PC mesh forwarding,
mobile lifecycle background/resume) is the natural follow-up scope and is called
out below — it should be promoted into its own features once this arc's harness is
proven, rather than ballooning this feature.

## Why this is a feature, not a story

It spans multiple subprojects (relay container, pi-extension, app client), needs a
real design pass to decide what to spin up vs service-level-mock, where the suite
lives, how it runs in CI vs locally, and how it asserts without becoming a brittle
re-implementation of the production code. Routes to `/agile-workflow:e2e-test-design`
once at `stage: drafting` (which it is).

## Strategic decisions

These are framing questions that shape the whole design. `e2e-test-design` will
resolve feature-internal choices; these set what the feature even *is*.

- **Live components vs service-level mocks**: Does the harness spin up a real relay
  container (the `remote-pi-relay` Docker image), a real pi-extension process
  (`dist/index.js` against the live SDK), and a real app client (Flutter
  `integration_test`, or a headless `dart:io`/Node WS client standing in for the
  app)? Or does it service-level-mock the boundaries (mock relay, drive the real
  extension + real app protocol layer)? The `e2e-test-design` skill defaults to
  service-level mocks; this bug class argues for at least one tier that runs the
  real relay + real extension together, because the bugs were in the *interaction*
  of real components, not in any one component's logic. — *Rationale: every bug
  this session was a contract mismatch at a real component boundary (SDK ctx
  shape, relay envelope rewrite, relay-required `room` field); mocks that don't
  reproduce the real boundary shape cannot catch them.*

- **Where the harness lives**: a new top-level `e2e/` dir, or under an existing
  subproject? The harness spans all three runtimes, so it likely needs its own
  home + runner rather than living inside `pi-extension/test/` or `relay/tests/`.

- **Run target**: local operator-runnable (so it can serve as the manual UAT
  backstop — see `story-release-uat-gate`), CI-runnable, or both? Memory/CAD
  constraints on the dev VM (the app APK build already needs heap-capping) are a
  real constraint on whether a real Flutter client can run in CI here.

- **Scope ceiling**: confirm pairing-arc-only for this feature, with reconnect /
  session-replacement / cross-PC / mobile-lifecycle as explicit follow-up
  features (not absorbed here). — *Locked: narrow-first; see "Out of scope".*

## What it must catch (regression contract)

At minimum, the suite must include cases that would have failed for each of the
three v0.6.0 bugs, so the bugs cannot regress:

1. **QR renders** — `/remote-pi pair` produces a `display:true`
   `remote-pi:pair-code` message that the (real or mocked) Pi TUI actually
   renders, after a real `session_start` (ctx without `sendMessage`).
   Catches `bindSessionContext` nulling the projection's `messageApi`.
2. **Pair_request reaches the Pi across rooms** — app (authed in `main`) sends
   `pair_request` targeting the Pi's cwd-room; the Pi receives it (relay rewrite
   delivers `outer.room='main'`) and replies `pair_ok`. Catches the recipient-side
   room guard.
3. **Post-pair traffic reaches the app** — after `pair_ok`, the Pi's outbound
   frames (`session_history`, `agent_chunk`) carry `room` and are accepted by the
   relay (not rejected `missing field room`) and delivered to the app. Catches the
   `PlainPeerChannel` missing-`room` regression.

The `e2e-test-design` pass will also add golden-path completeness, failure-mode
(relay down mid-pair, auth signature mismatch, token expiry/consumed), and the
tautology check (suite must not just re-assert what unit tests already prove).

## Out of scope (follow-up features, not this one)

- Reconnect / liveness-watchdog recovery (relay drop → re-pair or rehydrate).
- Session replacement (`/new`, `/fork`, `/resume`) end to end.
- Cross-PC mesh forwarding (`pi_envelope` / `pi_envelope_in`, `to_room`).
- Mobile lifecycle (background/resume, silent disconnect recovery).
- Cockpit desktop client coverage.

These are the broader cross-component program. Promote each into its own
`[testing]` feature once this harness's infrastructure is proven, so the
infrastructure cost is paid once and reused.

## Context

- The three fixed bugs and their root-cause analysis live in
  `.work/active/stories/story-pair-code-qr-not-rendering.md`,
  `story-pair-request-cross-room-dropped.md`, and
  `story-peer-channel-room-required.md`, plus the debugging arc in
  `.work/SESSION-NOTE-2026-07-02-paired-deploy-debugging.md`. These are the
  regression-contract source.
- Companion process item: `story-release-uat-gate` — the manual human backstop
  that would have caught the gap *today*; this feature is the durable
  automation that catches it going forward. No inter-dependency.

## Next

`/agile-workflow:e2e-test-design` picks this up at `stage: drafting`, resolves the
strategic decisions above into a concrete design (taxonomy, infrastructure,
journey coverage), writes the design into this body, and spawns child stories
with `depends_on` chains advancing `drafting → implementing`.

## Design decisions

- **Live product boundary**: Run the real Rust relay image, the real
  `pi-extension/src/index.ts` factory through the installed Pi SDK runtime, and
  the app's real `WsTransport` → `performPairing` → `PlainPeerChannel` →
  `ConnectionManager` → `SyncService` path. Only the external Pi host/TUI and
  mobile secure-storage service are substituted. This preserves all three
  escaped integration seams while keeping the suite headless.
- **Harness home**: Put orchestration in top-level `e2e/`, the Pi host adapter
  under `pi-extension/test/support/`, and the Flutter driver under
  `app/test/e2e/`. Stack-specific support therefore compiles against existing
  dependency graphs instead of creating hand-mirrored protocol packages.
- **Run target**: One `e2e/run-pairing.sh` command is both local and CI entry.
  Compose supplies service isolation; `flutter test --concurrency=1` drives the
  journey without an emulator or APK build, appropriate for the shared 11G VM.
- **State isolation**: Restart the Pi-host process between cases and use fresh
  temp HOME/cwd/Hive/keychain state. The extension runtime coordinator and QR
  token are process-global; an in-process reset would be less faithful.
- **Scope/taxonomy**: End after `session_history` materializes in the app's
  canonical transcript. Add golden and predictable failure-mode coverage only.
  Reconnect recovery, replacement, cross-PC, mobile background/resume, Cockpit,
  chaos, and fuzzing stay out of this feature.
- **Current command name**: Invoke `/outpost-pi pair`; `/remote-pi pair` in the
  incident brief names the pre-rebrand failure, not a compatibility command.
- **Dispatch/review**: Direct reads mapped relay, extension, app, and tests. This
  delegated worker has no nested generic subagent adapter, so design-time
  advisory review is unavailable and non-blocking. Implementation review weight
  remains caller-supplied `standard`.

## Architectural choice

### Option A — Service-composed product with headless boundary adapters (chosen)

Compose the real relay, real extension factory, and real app transport/sync
adapters. A small HTTP-controlled Pi-host service supplies the external Pi SDK
host lifecycle and captures user-visible TUI messages; Flutter tests supply the
mobile client and real Hive projection. This preserves every escaped contract
boundary without requiring a phone or model provider.

### Option B — Full Pi TUI plus Flutter device integration

Launch the interactive Pi binary and an Android/iOS device. This is closest to
manual UAT, but terminal automation, emulator availability, model setup, and APK
cost make it slow and flaky. Physical-device UAT remains in
`docs/release-uat.md` rather than becoming the first automated tier.

### Option C — TypeScript-only integration with synthetic app frames

Start relay and extension in Vitest and hand-build app frames. It is cheap but
repeats the failure behind this incident: app auth, room demux, generated Dart
decoding, and transcript hydration would not run.

Option A is the least irreversible sound choice. It adds one reusable service
boundary without another protocol source of truth and can support separately
scoped lifecycle suites later.

## Mock-boundary plan

| Boundary | Substitute | Ladder decision |
|---|---|---|
| Relay | Real image from `relay/Dockerfile` | Product under test; SQLite uses an ephemeral volume. |
| Pi host/TUI/model provider | Custom Node service in `pi-extension/test/support/e2e_pi_host_server.ts`, containerized by `e2e/services/pi-host.Dockerfile` | No off-the-shelf Pi SDK host emulator exists. It loads the real extension through the installed SDK runner, emits realistic `session_start` (no `sendMessage`), invokes registered commands, and exposes only health/command/user-visible event endpoints. |
| Mobile client | Real app adapters in headless `flutter test` | Product under test; widget/device layers add no value to this wire arc. |
| Mobile Keychain/Keystore | In-process `flutter_secure_storage` platform fixture | Last resort: no portable Android Block Store/iOS Keychain service emulator exists for Linux CI. Only platform I/O is substituted; real `PairingStorage` serialization/lifecycle runs. |
| Network interruption | `ghcr.io/shopify/toxiproxy:2.12.0` | Off-the-shelf service mock between app and relay; the Pi host stays connected. |
| Transcript storage | Real per-case Hive files | Product under test; final evidence is the materialized app projection. |

The Pi host exposes no envelope-injection API. The app gets the URI from the
same `display:true` message an operator sees and sends all pairing/session frames
through production adapters and the real relay.

## Taxonomy plan

- **Golden — 3 regression cases**: QR publication after realistic
  `session_start`; cross-room `pair_request` (`app room=main` targeting a
  non-`main` cwd-room) through `pair_ok`; and post-pair `session_sync` through
  `session_history` to a Hive transcript row.
- **Failure — 4 cases**: invalid auth signature; consumed token; expired token;
  and Toxiproxy cutting the app relay path after QR generation. Each asserts a
  typed outcome and absence of corrupt persistence.
- **Chaos — not applicable**: reconnect/recovery is explicitly follow-up scope;
  the unavailable-relay test checks clean bounded failure, not recovery.
- **Fuzz — not applicable**: generated schema/codecs already own parser
  properties. This suite consumes those decoders instead of duplicating them.

## Trickiest unit first

The Pi-host service is riskiest. It must load production extension code through
the installed SDK runner, provide a real `session_start` context that lacks
message actions, connect the actual `RelayClient`, and remain a narrow external
host rather than a replacement implementation. Its API is command in and
rendered TUI/status out. Process restart is reset; no endpoint mutates tokens,
owner channels, envelopes, or session internals.

## Implementation Units

### Unit 1: Cross-component service scaffold

**Files**:
- `e2e/docker-compose.test.yml`
- `e2e/services/pi-host.Dockerfile`
- `e2e/run-pairing.sh`
- `e2e/README.md`
- `pi-extension/test/support/e2e_pi_host_runtime.ts`
- `pi-extension/test/support/e2e_pi_host_server.ts`
- `app/test/e2e/support/harness_endpoints.dart`
- `app/test/e2e/support/pi_host_client.dart`
- `app/test/e2e/support/eventually.dart`
- `app/test/e2e/support/secure_storage_fixture.dart`
- `app/test/e2e/support/toxiproxy_client.dart`
- `.github/workflows/e2e-pairing.yml`

**Story**: `feature-cross-component-e2e-pairing-suite-infra`

```ts
export interface PiHostStatus {
  readonly generation: string;
  readonly state: "idle" | "started" | "paired";
  readonly sessionId: string;
  readonly roomId: string;
  readonly relayConnected: boolean;
}

export interface PiHostTuiEvent {
  readonly seq: number;
  readonly kind: "tui_message" | "notification";
  readonly payload: unknown;
}

export class E2ePiHostRuntime {
  static start(options: {
    relayUrl: string;
    cwd: string;
    seededTranscriptText: string;
  }): Promise<E2ePiHostRuntime>;
  status(): PiHostStatus;
  invokeOutpostPi(args: string): Promise<void>;
  eventsAfter(seq: number): readonly PiHostTuiEvent[];
  dispose(): Promise<void>;
}
```

```dart
final class PiHostClient {
  PiHostClient(Uri baseUri);
  Future<PiHostStatus> waitUntilReady();
  Future<void> invokeOutpostPi(String args);
  Future<List<PiHostEvent>> eventsAfter(int sequence);
  Future<void> restartForIsolation();
}

Future<T> eventually<T>(
  Future<T?> Function() probe, {
  required Duration timeout,
  required String description,
});
```

**Implementation Notes**:
- Compose builds the real relay and custom Pi host plus pinned Toxiproxy. Use
  healthchecks, ephemeral volumes, and dynamic host ports.
- `run-pairing.sh` resolves ports with `docker compose port`, initializes the
  proxy, passes endpoints via `--dart-define`, runs serial Flutter tests, and
  always executes `down -v` in a trap.
- Before importing `src/index.ts`, the host creates fresh HOME/cwd config. It
  creates real SDK `SessionManager`/`ExtensionRunner`, binds deterministic host
  actions, emits `session_start`, and waits for production state `started`.
  `sendMessage` records TUI-visible output; the session context has no such API.
- `POST /__restart` responds then exits; Compose restarts a fresh process. Tests
  poll for a new generation instead of sleeping.
- Seed history through the SDK session/history surface before `session_start`,
  never by injecting `session_history` wire frames.
- CI calls the same runner and builds no APK/emulator.

**Acceptance Criteria**:
- [ ] One command starts healthy services, runs the suite, and cleans containers/volumes on every exit.
- [ ] Pi host runs the real factory through installed SDK and proves the session context lacks message actions.
- [ ] Restart removes prior token, peer file, SDK session, events, Hive data, and secure-storage state.
- [ ] Readiness uses bounded predicate polling with diagnostics, not arbitrary sleeps.
- [ ] CI and local use the same entrypoint.

---

### Unit 2: QR publication after real session start

**File**: `app/test/e2e/qr_lifecycle_e2e_test.dart`

**Story**: `feature-cross-component-e2e-pairing-suite-qr-lifecycle`

**Invariant**: After a real Pi session starts and the operator invokes
`/outpost-pi pair`, the Pi surface displays a parseable, room-targeted code.

```dart
test('session_start then pair displays a usable QR message', () async {
  final status = await host.waitUntilReady();
  await host.invokeOutpostPi('pair');
  final event = await trace.waitForPairCode();
  expect(event.display, isTrue);
  expect(event.customType, 'outpost-pi:pair-code');
  final qr = QrPairPayload.tryParse(event.uri);
  expect(qr, isNotNull);
  expect(qr!.roomId, status.roomId);
  expect(qr.roomId, isNot('main'));
});
```

**Setup/teardown**: Fresh Pi-host process connected to relay with deterministic
non-`main` cwd-room; restart host and clear secure storage afterward.

**Acceptance Criteria**:
- [ ] Fails if `bindSessionContext` clears the API armed by `bindApi`.
- [ ] Observes an SDK-accepted TUI message, not `buildQRUri` or a mock call count.
- [ ] Failure trace excludes token, key, signature, and transcript contents.

---

### Unit 3: Cross-room pair request through pair_ok

**Files**:
- `app/test/e2e/support/pairing_stack.dart`
- `app/test/e2e/cross_room_pairing_e2e_test.dart`

**Story**: `feature-cross-component-e2e-pairing-suite-cross-room-pairing`

**Invariant**: An app authenticated in `main` can target the Pi's cwd-room,
receive `pair_ok`, and persist the confirmed room without timeout.

```dart
final class PairingStack {
  static Future<PairingStack> connect({
    required HarnessEndpoints endpoints,
    required QrPairPayload qr,
    required PairingStorage storage,
  });
  Future<PairingResult> pair({required String deviceName});
  Future<HydratedSession> adoptAndHydrate(PairingResult result);
  Future<void> close();
}

final class HydratedSession {
  const HydratedSession({
    required this.peer,
    required this.sessionId,
    required this.channel,
    required this.connection,
    required this.sync,
  });
  final PeerRecord peer;
  final String sessionId;
  final PlainPeerChannel channel;
  final ConnectionManager connection;
  final SyncService sync;
}
```

**Implementation Notes**:
- Generate a real owner key, connect production `WsTransport` to Toxiproxy with
  app auth room `main` and destination room from production QR parsing, then call
  production `performPairing`.
- Never decode or construct outer envelopes in the test. Keep the successful
  transport open for Unit 4 and transfer ownership to production channel/manager.

**Acceptance Criteria**:
- [ ] Fails if recipient code again compares the relay-rewritten sender room with the Pi room.
- [ ] App authenticates in `main`, targets a different room, and saves real `pair_ok` output.
- [ ] Uses generated decoder and production storage; no test-local `pair_ok` map or envelope mirror.

---

### Unit 4: Post-pair session transcript hydration

**File**: `app/test/e2e/session_hydration_e2e_test.dart`

**Story**: `feature-cross-component-e2e-pairing-suite-session-hydration`

**Invariant**: After `pair_ok`, the app learns canonical session identity, sends
`session_sync`, receives room-addressed `session_history`, and materializes the
seeded transcript in the active Hive session.

```dart
test('pair_ok is followed by canonical transcript hydration', () async {
  final paired = await stack.pair(deviceName: 'E2E Phone');
  final session = await stack.adoptAndHydrate(paired);
  await session.channel.send(SessionSync(
    id: uuid7(),
    sessionId: session.sessionId,
  ));
  final rows = await trace.waitForTranscriptRows(session);
  expect(rows.map((row) => (row.role, row.text)), contains(
    (MsgRole.user, seededTranscriptText),
  ));
  expect(rows.every((row) => row.pending == false), isTrue);
});
```

**Setup/teardown**: Start Pi SDK host with one persisted user entry. Initialize
`LocalBoxes.initForTest` in a new directory; `ConnectionManager.adopt` owns the
production channel and `SyncService.activate` binds `(peer, room, session_id)`.
Dispose sync, manager, channel, Hive, temp files, and secure storage in owner
order.

**Acceptance Criteria**:
- [ ] Fails if extension `PlainPeerChannel` omits destination `room`.
- [ ] Fails if app drops the delivered sender room or rejects session identity.
- [ ] Success is a materialized transcript row, not merely seeing a wire frame.
- [ ] Every socket, stream, timer, box, and temp directory has teardown ownership.

---

### Unit 5: Pairing failure-mode contracts

**File**: `app/test/e2e/pairing_failures_e2e_test.dart`

**Story**: `feature-cross-component-e2e-pairing-suite-failure-modes`

**Invariants**:
- Invalid auth never reaches pairing and does not consume the QR token.
- Consumed/expired tokens return typed `pair_error` and do not corrupt peers.
- Relay disappearance after QR fails within deadline and stores no peer.

```dart
group('pairing failure modes', () {
  test('invalid relay auth is rejected before pair_request', () async {});
  test('single-use token rejects the second owner', () async {});
  test('minimum-TTL token expires before use', () async {});
  test('relay unavailable after QR does not persist a peer', () async {});
});
```

**Implementation Notes**:
- The invalid-auth probe speaks only hello/challenge/auth and signs wrong bytes;
  a later valid production pair with the same QR proves no token consumption.
- The consumed case uses a second real app identity and unchanged first record.
- Expiry uses production `pair --ttl 10`; do not add a product clock hook.
- Disable Toxiproxy only on the app path and restore it in `addTearDown`.

**Acceptance Criteria**:
- [ ] Each failure asserts typed/user-visible outcome and absence of corrupt persistence.
- [ ] No assertion/log contains challenge, signature, token, key, or transcript content.
- [ ] Network failure is service-level; no mocked WebSocket client.
- [ ] Serial execution leaves proxy healthy and host generation fresh.

## Implementation Order

1. `feature-cross-component-e2e-pairing-suite-infra`
2. `feature-cross-component-e2e-pairing-suite-qr-lifecycle`
3. `feature-cross-component-e2e-pairing-suite-cross-room-pairing`
4. `feature-cross-component-e2e-pairing-suite-session-hydration`
5. `feature-cross-component-e2e-pairing-suite-failure-modes`

Stories are durable checkpoints, not worker targets; one feature owner should
normally carry the bundle. Failure modes can follow the cross-room baseline
while hydration is finalized, but the declared DAG remains explicit.

## Simplification

- Reuse generated codecs, QR parser, app transport/sync, relay image, and SDK
  runner. The e2e layer owns no ClientMessage/ServerMessage/envelope registry.
- Keep one polling helper and ordered lifecycle trace instead of per-test sleeps.
- Retain existing fast unit/integration regressions for localization; this suite
  proves composition and removes none of them.
- Do not generalize the harness for follow-up lifecycle arcs yet.

## Testing integrity contract

Every child story follows `.agents/rules/testing-integrity.md`:

- Park any exposed production bug and land the honest failing test as a linked
  skip with one-line reason; never weaken its invariant.
- Fix stale fixtures, drifted assertions, and harness defects in-session.
- Never use placeholder truths, mock-call assertions, snapshots-only evidence,
  broadened mocks, or deleted failures to obtain green.
- Stable success is TUI output, typed pair result, persisted peer, or materialized
  transcript—not internal call traces.

## Risks

- **Pi-host fidelity**: A hand context could repeat the original mistake.
  Mitigation: use installed SDK `session_start` and assert the emitted context
  lacks message actions; if necessary use the private SDK factory loader already
  proven by `runtime_coordinator.integration.test.ts`, not a wider fake.
- **Process-global bleed**: Coordinator/token survive in-process reset.
  Mitigation: process restart only, generation polling, fresh temp storage.
- **Readiness flakes**: Auth/metadata are asynchronous. Mitigation: healthchecks
  and bounded state predicates; no fixed startup sleeps. Diagnostics contain
  phase/type/room/byte count only.
- **TTL cost**: Production minimum is 10 seconds. Keep one expiry case rather
  than adding a clock seam solely for test speed.
- **Host networking**: Dynamic Compose ports must work on Linux and Docker
  Desktop. If host-mapped Toxiproxy fails, fallback is a containerized Flutter
  driver, not in-process socket mocks.
- **Scope pressure**: Reconnect and replacement remain separately promoted
  features after this first harness proves itself.
