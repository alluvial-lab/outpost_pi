---
id: feature-mobile-session-context-telemetry
kind: feature
stage: done
tags: [pi-extension, app, ux, protocol]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-09-07
updated: 2026-09-07
---

# Mobile parity for TUI footer telemetry: git branch, ctx %, max ctx

## Brief

The pi TUI footer shows `git branch`, `ctx ▰▰▰▰▱ 92% · max 1m` — surface the
same on mobile (operator ask, 2026-09-07). Additive optional fields on
`roomMeta`/`roomMetaPatch`/`helloRoomMeta` (`branch`, `ctx_percent`,
`ctx_max`), riding the exact additive-room-meta rails proven by the
`background` field (d13b85fec): schema + codegen + relay merge/broadcast +
extension publish + app render.

One real investigation point: the extension-visible SDK surface for context
usage/max (the TUI renders it, so the session knows it — find the surface:
session header, usage events, sessionManager). Everything else is a
well-trodden recipe.

## Strategic decisions

- None at scope time — the framing is fully pinned by the proven
  `background`-field recipe; remaining choices (ctx_max raw vs humanized,
  publish thresholds, render placement) are feature-design calls.

## Simplification opportunity

- **Single-schema-touch batching**: if other telemetry fields are wanted
  later, land them in this one schema pass, not N passes (sequencing note
  from the park — resist scope creep the other way too: only fields the
  operator actually asked for).
- **SDK surface before subprocess**: check whether the SDK exposes the git
  branch to extensions before shelling out — a shell-out per publish is a new
  process lifecycle to own; prefer an SDK surface if one exists.
- **Raw numbers, app-side formatting**: `ctx_max` as a raw token count; the
  app humanizes ("1m") — keeps the extension dumb and the render flexible.

## Design decisions

- **App render placement — both surfaces** (operator, 2026-09-07): chat
  header compact line `main · 92% of 1m` (full info while driving) AND
  Home session-tile idle subtitle suffix `· 92%` (glanceable fleet state;
  percent only — no branch/max clutter on tiles).
- **Pressure tint — yes** (operator, 2026-09-07): at `ctx_percent >= 85`
  the percent text tints amber (`colors.warning`, the same pressure semantic
  as reconnecting); branch text stays muted either way.
- **ctx source = `ctx.getContextUsage()` pull** — SDK 0.84.3 exposes
  `ContextUsage { tokens: number|null, contextWindow: number, percent:
  number|null }` on the extension context (the exact TUI-footer source;
  verified `core/extensions/types.d.ts:193,244`). Sampled at `session_start`,
  `agent_start`, `agent_settled`, `session_compact` — NOT per-message.
  `tokens/percent: null` (right after compaction) is meaningful: publish a
  null-clear so stale values don't linger.
- **branch source = git subprocess** — the SDK does NOT expose git branch
  (verified; only the TUI's `interactive-mode.js` shells out, so the TUI
  parity is literally the same mechanism). Shell `git branch --show-current`
  in the session cwd at session start + turn boundaries, value-compared;
  empty output (detached HEAD / not a repo) / timeout → null-clear.
- **Merge semantics** — `branch` joins `nullableStrings` (set / clear /
  preserve); `ctx_percent` + `ctx_max` get a NEW `nullableIntegers` merge
  category (set / clear / preserve) because post-compaction unknown must
  CLEAR a stale percent, which absence-preserve cannot express.
- **Publish gating** — value-compare against last-published state; publish
  only changed fields, as one patch per sample. Integer percent + max +
  branch string equality is the quantization (TUI parity); no extra
  thresholding.
- **Wire posture** — purely additive optional fields; old peers ignore
  them. NOT a paired-deploy cutover (no entry in the repo's
  paired-wire-changes list is needed).
- **Design-time advisory review skipped** (risk-driven policy): small
  feature assembling a proven recipe; the one novel surface (nullable-int
  codegen category) is pinned by goldens + relay merge tests.

## UI alignment

ux-ui plugin installed; no parent epic to inherit mocks from. Skipped as
minor composition reusing existing patterns: mono-12 text in the existing
chat status area, existing tile subtitle, existing `colors.warning`. No
mocks produced.

## Architectural choice

**Additive room-meta fields sampled by the extension** (the `background`
recipe extended), over (a) chat-stream events — chatty, pollutes the sealed
message path, and Home tiles need the data without chat open; and (b)
app-side polling via a new control command — new command surface + poll loop,
no push on change. Room-meta rides rooms snapshots (tiles), presence_check/
room_announced (fleet state), and helloRoomMeta (fresh attach) for free —
that's why the recipe exists.

## Implementation Units

### Unit 1: schema + nullableIntegers codegen + relay merge
**File**: `protocol/schema/relay-control.schema.json`,
`tools/protocol-codegen/bin/protocol-codegen.mjs`, regenerated
`relay/src/protocol/generated/{control,room}.rs` +
`pi-extension/src/protocol/generated/protocol.generated.ts` +
`app/lib/protocol/generated/relay_frames.g.dart`,
`protocol/fixtures/relay/relay-control.jsonl`, `relay/src/rooms.rs`,
`relay/src/peers/{registry.rs,registry_event_publisher.rs}`,
`relay/src/handlers/{control.rs,connection_actor.rs,pi_forward.rs}`
**Story**: `feature-mobile-session-context-telemetry-schema-codegen`

Schema: add to `roomMeta`, `roomMetaPatch`, `helloRoomMeta`:
`"branch": { "type": ["string","null"], "maxLength": 256 }`,
`"ctx_percent": { "type": ["integer","null"], "minimum": 0, "maximum": 100 }`,
`"ctx_max": { "type": ["integer","null"], "minimum": 0 }`.
mergePatchSemantics becomes
`nullableStrings: ["model","thinking","session_id","branch"]` +
new `nullableIntegers: ["ctx_percent","ctx_max"]`.

Codegen (all emitters live in `bin/protocol-codegen.mjs`):
- `nullableIntegerPatchFields()` reader mirroring `nullableStringPatchFields()`
  (~line 1634); thread through `emitRustRoom` (~1651).
- `rustTypeForRoomMetaField` (~1625): accept `{type:"integer"}` → `u64`
  (both fields; percent's 0-100 bound is schema-validated, not a Rust type).
- Rust patch emitter: `nullableIntegers` → `pub ctx_percent:
  Option<Option<u64>>` + `#[serde(skip_serializing_if)]`, and the custom
  `Deserialize` Visitor below it gains u64 arms.
- TS emitter: patch/frame nested metas gain `branch?: string | null;
  ctx_percent?: number | null; ctx_max?: number | null;`
  (RoomMetaUpdate/RoomMetaUpdated meta, hello room_meta, presence_check
  rooms, room_announced — 5 sites in `protocol.generated.ts`).
- Dart emitter: `int?` + null-clear sentinel participation wherever the
  nullable strings already participate.
- Fixtures: set / clear / preserve rows for all three fields.

Relay hand-code (exactly the lines d13b85fec touched per field):
`RoomMetaPatch::is_empty()` += 3 fields (`rooms.rs:37`); merge in
`apply_patch` (absent=preserve, `Some(None)`=clear, `Some(Some(v))`=set);
`registry.rs` snapshot paths + `registry_event_publisher.rs` broadcast +
`control.rs`/`connection_actor.rs`/`pi_forward.rs` forwarders carry the
fields opaquely.

**Acceptance Criteria**:
- [ ] Codegen suite green with updated goldens/fixtures (set/clear/preserve for all three fields)
- [ ] Relay test: patch set→snapshot shows values; null-clear→snapshot cleared; absent→preserved
- [ ] `cargo fmt --check && cargo clippy -- -D warnings && cargo test` green
- [ ] SPEC.md room-meta wire-contract line gains the three fields (code-first, same commit set)

### Unit 2: extension telemetry sampler
**File**: new `pi-extension/src/extension/session_telemetry.ts`; wiring in
`pi-extension/src/index.ts`; type extension in
`pi-extension/src/extension/relay_transport.ts` (`sendRoomMeta` patch param)
**Story**: `feature-mobile-session-context-telemetry-extension-sampler`

```ts
import type { ContextUsage } from "@earendil-works/pi-coding-agent";

/** Room-meta telemetry patch fields owned by the sampler. */
export type SessionTelemetryPatch = {
  branch?: string | null;
  ctx_percent?: number | null;
  ctx_max?: number | null;
};
/** Reads fresh context usage; undefined when no fresh session ctx exists. */
export type ContextUsageSource = () => ContextUsage | undefined;
/** Resolves the session cwd; undefined before first session_start. */
export type CwdSource = () => string | undefined;

export class SessionTelemetryPublisher {
  constructor(opts: {
    publish: (patch: SessionTelemetryPatch) => void;
    usage: ContextUsageSource;
    cwd: CwdSource;
    runGitBranch: (cwd: string, timeoutMs: number) => Promise<string | null>;
    gitTimeoutMs?: number; // default 2000
  })
  onSessionStart(): void    // sample usage + branch; publish all known fields
  onAgentStart(): void      // sample usage only
  onAgentSettled(): void    // sample usage + branch (checkouts land between turns)
  onSessionCompact(): void  // sample usage (post-compaction null ⇒ clear)
  reset(): void             // session boundary: forget last-published state
  stateForTest(): { branch: string | null; ctxPercent: number | null; ctxMax: number | null }
}
```

Behavior: value-gated delta-only publishes; one patch per sample even when
several fields change; concurrent git call coalesced (skip if in flight,
apply + compare on arrival); git timeout/empty → `null` (clear, published
once); usage `undefined` (no model yet) → no ctx fields in that patch.

Wiring in `index.ts`: usage accessor resolves from the LATEST captured
session ctx slot each call — never a captured ctx object — and swallows
stale-context errors (`_isStaleContextError` pattern) returning `undefined`;
this is the known wedge class (see `story-new-wedge-bare-pi-reopen`). Call
sampler at the existing `session_start` / `agent_start` / `agent_settled` /
`session_compact` handler sites (the working/background bracketing sites).
Extend `_myRoomMeta` + `_publishRoomMetaPatch` + hello room_meta with the
three fields.

Cleanup folded in (scan-protocol-contract): `_publishRoomMetaPatch`'s
hand-enumerated patch literal type derives from the generated
`RelayControlFrameRoomMetaUpdate["meta"]` Pick instead of re-listing fields,
if the generated export permits; note in the story if it doesn't fit.

**Acceptance Criteria**:
- [ ] Unit tests (injected fakes): no republish on unchanged values; delta-only patch contents; null-clear after compaction; git timeout → null-clear once; reset forgets state
- [ ] Wiring test: agent_settled triggers a sample; stale-throwing usage source returns undefined without throwing
- [ ] `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build` green
- [ ] Live spot-check on one restarted pi: published ctx_percent matches the TUI footer at settle

### Unit 3: app model + render + tint
**File**: `app/lib/protocol/control_frames.dart` (RoomInfo + patch apply),
`app/lib/ui/chat/chat_page.dart` (header line), new
`app/lib/ui/chat/ctx_format.dart` (pure formatter),
`app/lib/ui/home/widgets/session_tile.dart` (idle subtitle suffix)
**Story**: `feature-mobile-session-context-telemetry-app-render`

- `RoomInfo` += `final String? branch; final int? ctxPercent; final int?
  ctxMax;` with `_kRoomInfoUnset` sentinel participation in `copyWith`
  (null-clear capable), `fromJson`/`toJson`, `==`/`hashCode`; patch
  application follows absent=preserve / null=clear / value=set.
- `ctx_format.dart`:

```dart
/// Humanize a raw token ceiling the way the TUI footer does: 1000000 → "1m",
/// 272000 → "272k"; falls back to the raw number when < 1000.
String formatCtxMax(int tokens);
/// "main · 92% of 1m" — omits the max segment when ctxMax is null,
/// the whole string when percent is null.
String formatCtxTelemetryLine({String? branch, required int? percent, int? maxTokens});
```

- Chat header: mono-12 line in the existing status area; percent span
  (and tile suffix) `colors.warning` when `percent >= 85`, else
  `colors.muted`; branch span always muted.
- Session tile: when NOT working, append `· NN%` to the idle subtitle when
  `ctxPercent != null`; tinted the same way.

**Acceptance Criteria**:
- [ ] Widget test: header renders `main · 92% of 1m`; `>= 85` percent span is warning-colored; null percent renders no telemetry line
- [ ] Tile test: idle subtitle gains `· 92%`; working tile shows no percent
- [ ] Formatter unit tests (1m / 272k / raw / boundary 85)
- [ ] Patch-apply test: set → shown; null → cleared; absent → preserved
- [ ] `flutter analyze && flutter test --exclude-tags e2e` green

---

## Implementation Order

1. `…-schema-codegen` (wire contract; everything compiles against it)
2. `…-extension-sampler` ∥ `…-app-render` (independent sides of the wire;
   both depend only on 1)

## Simplification

- The `_publishRoomMetaPatch` type re-enumeration cleanup (Unit 2) is the one
  concrete deletion: one fewer hand-maintained copy of the wire patch shape.
- No new e2e lane: additive fields ride the existing pairing suite's meta
  rails; deliberately NOT extended per-field (proportional rigor).
- Nothing else deleted — the area is already tight from the background pass.

## Testing

- **Wire contract**: codegen goldens + relay-control.jsonl fixture rows
  (set/clear/preserve × 3 fields) — protects the one novel surface
  (nullableIntegers) against emitter drift across three languages.
- **Relay merge**: rooms_test pattern — null-clear is the regression this
  design specifically must not lose (stale percent after compaction).
- **Sampler gating**: unit tests with injected sources — protects the
  bounded-publish invariant (edge-gated, never per-message).
- **Stale-ctx accessor**: wiring test — protects the highest-risk defect
  class in this repo (post-replacement ctx use).
- **Render**: widget + formatter tests as listed; no golden images.
- **Removed**: none (new surface); note — existing background tests stay
  untouched as the recipe's regression net.

## Risks

- **Stale session ctx** (highest, known wedge class): mitigated by
  latest-slot accessor + `_isStaleContextError` guard + test; sampler never
  holds a ctx reference.
- **`getContextUsage()` freshness at agent_settled** — assumption that
  settled-time values are current (it's the footer's source, so high
  confidence); Unit 2 acceptance includes a live spot-check; fallback if
  stale: also sample at `message_end` (still turn-bounded, not per-delta).
- **Codegen emitter/visitor gap** (new category × 3 languages): pinned by
  goldens + fixtures + all three subprojects building green in CI.
- **App patch-apply asymmetry**: null-clear tested explicitly.
- **git subprocess pathology** (network-fs cwd, huge repo): 2s timeout →
  null; no retry loop.
- **Snapshot size growth**: 3 small fields per room — negligible.

## Implementation summary

All three implementation stories are now `stage: done`:

- `feature-mobile-session-context-telemetry-schema-codegen` landed the
  additive schema/codegen projections, nullable-integer patch category, relay
  tri-state merge, and generated TypeScript/Rust/Dart consumers.
- `feature-mobile-session-context-telemetry-extension-sampler` landed the
  edge-gated extension sampler, fresh-session context usage accessor, git
  branch lookup, lifecycle sampling, null-clears, and hello metadata
  projection.
- `feature-mobile-session-context-telemetry-app-render` landed the Dart room
  telemetry model, sentinel-backed patch semantics, compact formatter, chat
  header line, Home idle-tile suffix, pressure tint, and focused tests.

The app story intentionally stayed within its explicit write scope. Its
`RoomMetaUpdated.applyTo` helper and protocol tests make absent-preserve,
null-clear, and value-set behavior executable. The existing
`ConnectionManager` hand-applies the older metadata fields and was out of
scope for this story; if incremental telemetry patches are not followed by a
snapshot in production, that consumer needs a separately scoped follow-up.
This is a consumer-boundary discovery, not a change to the wire contract.

## Integrated verification

- `cd app && ../.tools/flutter/bin/flutter analyze` — passed with no issues.
- `cd app && ../.tools/flutter/bin/flutter test --exclude-tags e2e` — passed,
  1,024 tests, with only the repository's existing google_fonts network-load
  warnings printed by theme tests.
- Story-specific formatter, protocol patch, chat-header, and session-tile
  tests passed in the focused run.
- Story 1 and Story 2 verification remained green at their recorded commits;
  no pi-extension or relay lanes were rerun here per the feature boundary.

Implementation commits: `2d9cbd29f`, `8d807cc5c`, `87ce1b6b7`.

## Implementation notes (2026-09-07)

- Stories landed: schema-codegen (2d9cbd29f), extension-sampler (8d807cc5c),
  app-render (87ce1b6b7); feature roll-up 295bb7cea.
- **Integration fix (post-roll-up, pre-review)**: the app-render worker's
  discovery was confirmed real — `ConnectionManager`'s `RoomMetaUpdated` case
  re-derived the patch field-by-field and dropped the telemetry trio on live
  broadcasts (snapshots only). Fixed by routing through
  `RoomMetaUpdated.applyTo` (the story's single-source tri-state impl),
  deleting the duplicated merge logic; regression test added
  (set → preserve → null-clear through the live cache path). All 1,025 app
  tests green post-fix.
- Extension-sampler live spot-check DEFERRED to operator at deploy (requires
  one pi restart; the orchestrating session runs on this fleet) — recorded
  in the story body.

## Review fixes

Four confirmed telemetry blockers were repaired in the integration boundary:

- **App announcement/snapshot hydration** — `ConnectionManager` rebuilt rooms
  without carrying the additive telemetry fields, so room announcements and
  older snapshots erased live branch/context values. It now preserves cached
  values when those optional fields are omitted, including PairOk session
  reconstruction; regression coverage exercises announcement → live patch →
  PairOk and an omitted-field snapshot.
- **Relay null-clear broadcast** — the relay merged explicit telemetry clears
  but its subscriber projection omitted nullable fields whose value was null.
  Broadcasts now include branch, context percentage, and context maximum as
  explicit JSON nulls when cleared; the relay test covers set and null-clear.
- **Delayed branch sampling** — an asynchronous git lookup published the
  usage captured before compaction and dropped newer settled samples while a
  lookup was in flight. The sampler now re-reads usage on branch completion
  and publishes usage-only deltas during lookup coalescing.
- **Connect-time telemetry loss** — samples cached while relay authentication
  was pending were value-gated away after the socket became live. The
  connection callback now replays the sampler's current projection; a
  deferred-connect wiring test proves the first post-connect update is sent.

Review regression tests passed:

- `app`: focused `connection_manager_test.dart` (all 60 tests).
- `relay`: `cargo fmt --check && cargo clippy -- -D warnings && cargo test`
  (172 unit, 8 integration, 14 mesh, 9 forwarding, 10 presence, 3 protocol,
  and 20 rooms tests).
- `pi-extension`: sampler unit tests (8) and deferred-connect wiring test;
  protocol check, typecheck, and build passed.

Known unrelated verification findings: the full pi-extension suite currently
has two stale fixture-count assertions expecting 41 files while the checked-in
catalog contains 43; the full app suite had three pre-existing/flaky failures
(auth-read hedge timeout and two chat ViewModel timing cases). No deployed
live spot-check was possible in this session; operator verification remains
required after a Pi restart.

## Review closure (2026-09-07, standard weight)

One cross-model pass (GPT-6 Astra vs Luna implementers) → 4 blockers, all
receiver-confirmed and fixed in 40b1f70b3 (snapshot/announcement/pairing
telemetry preservation; relay explicit-null broadcasts for clears; usage
re-read after delayed git + overlap coalescing; post-auth telemetry replay).
Fixes verified green (focused suites per surface; full-suite caveats are the
known sync_service load-flake and the fleet fixture-count assertion owned by
the fleet fix round). Closed without a second pass per standard weight.
Deferred to operator at deploy: the live ctx-percent spot-check vs TUI footer
(requires one pi restart).
