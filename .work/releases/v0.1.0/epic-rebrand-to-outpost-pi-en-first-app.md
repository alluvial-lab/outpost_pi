---
id: epic-rebrand-to-outpost-pi-en-first-app
kind: feature
stage: done
tags: [rebrand, docs, i18n, app]
parent: epic-rebrand-to-outpost-pi-en-first
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
---

# EN-first + dartdoc gap-fill — app

## Brief

Translate Portuguese → English and adopt the dartdoc documentation framework
in `app/` (Flutter mobile). 21 PT-bearing files under `app/lib/` (0 in tests).
PT is predominantly comment prose; the few user-facing string literals
(onboarding `welcome_step.dart`, update-banner copy) need translation-review,
not mechanical sed — the design pass must distinguish the two.

Covers `app/lib/` only. Gap-fill scope is the Always tier per the doc
convention: exported Dart classes/functions from shared/domain layers,
ViewModel exports, service-layer functions, `Result`/`Either`-returning
functions. The app's `domain/contracts/` and `domain/value_objects/` are the
contract-bearing surfaces most likely to need gap-fill.

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi-en-first`
- Position in epic: independent mid-size slice. No `depends_on` — the app's
  wire-stable identifiers (auth string, applicationId) already migrated in the
  first rebrand epic. Can run in parallel with every other child feature.

## Foundation references
- `.agents/skills/documentation-conventions/SKILL.md` — dartdoc `///` format
  and the Always tier for Dart (exported declarations, ViewModel exports,
  `Result`-returning functions).
- `.agents/skills/flutter-mobile/SKILL.md` — app code reference; read before
  editing `app/`.
- Parent epic `## Grounded surface measurement` — the 21-file count (the
  first rebrand epic's "~23" estimate holds).
- Parent epic `## Decomposition risks` — "user-visible UI text needs review,
  not just mechanical translation" applies here (onboarding/update copy).

## What this feature does NOT cover
- Wire-stable identifiers (auth string, applicationId) — owned by the first
  rebrand epic's wire-stable migration feature, already shipped.
- Product-identity string renames — owned by the mechanical-rename feature.
- `scripts/` shell comments — out of scope (operator glue).
- Generated/vendored state (`.dart_tool/`, `.pub-cache/`, build output).

## Verification
```bash
# from app/
flutter analyze && flutter test
```
Plus a grep confirming zero PT (accented Latin) in `app/lib/`.

## Design decisions

- **How is the 21-file translation surface partitioned?**: Use three disjoint
  ownership slices (`domain/`, data/shared infrastructure, and `ui/`) — this
  keeps implementation parallelizable without two workers editing the same
  Dart library.
- **What counts as a gap-fill declaration?**: Apply the convention's
  intent-based Always tier to public top-level domain/shared declarations,
  contract methods, service/repository lifecycle surfaces, ViewModel classes,
  and functions returning discriminated unions or throwing typed errors.
  Constructors, fields, generated protocol DTOs, barrel exports, adapter
  overrides that inherit a documented contract, and self-evident DTO accessors
  stay in Skip/Recommended; documenting all 177 baseline gaps would violate the
  convention by creating obvious-description noise.
- **How are runtime strings handled?**: Never bulk-replace quoted literals.
  Review the five Portuguese `FormatException` messages in
  `domain/entities/update_info.dart` as observable error text, and review the
  existing EN onboarding/update-banner copy in place for tone and meaning.
  The current `welcome_step.dart` and `update_banner.dart` literals are already
  English; implementation should preserve or deliberately improve them, not
  invent a translation diff merely to satisfy the work item.
- **How is “zero PT” proved?**: Treat the fixed 21-file manifest as primary,
  then use both an accented-Latin scan and a Portuguese-token/comment scan.
  The accent scan alone is necessary but insufficient because words such as
  `para`, `com`, and `sem` are ASCII.
- **Discovery/dispatch rationale**: Direct-read only for design. The feature is
  broad in file count but bounded by an exact 21-file manifest and a mechanical
  declaration audit; exploratory fanout would duplicate local evidence. The
  three child stories provide raised-tier implementation ownership. Advisory
  cross-model review was skipped because this is low-risk documentation/copy
  work with no architectural choice or irreversible product decision.

## UI alignment

No mockup is required. This feature introduces no screen, flow, component, or
layout change; it only reviews existing copy on the onboarding welcome step and
update banner. The parent epic has no mockups, and no genuinely-new UI surface
emerged that would justify feature-level fallback mockups.

## Architectural choice

Use a **manifest-driven, three-story pass**. Each story first translates only
comments/prose in its owned files, then performs an intent-based dartdoc audit
and gap-fill in that same ownership boundary. Runtime literals are isolated for
human-style review before editing. Every story can run independently; the
feature-level integration gate scans all of `app/lib/` and runs the app suite.

Alternatives rejected:

1. **One bulk translation + one global dartdoc pass** is superficially fastest,
   but mixes behavior-neutral comments with observable strings and gives one
   worker an unnecessarily large context/diff.
2. **One story per file** makes ownership obvious but creates 21 tiny items,
   repeated setup, and no useful dependency signal.
3. **Three layer-owned stories** (chosen) balance reviewability and parallel
   ownership while preserving the app's `ui -> domain <- data` boundaries.

## Translation manifest

### Comment/prose-only lane (safe for bounded translation; not blind `sed`)

The following files contain PT only in comments/dartdoc or agent guidance. The
implementation may translate their prose without changing executable tokens,
identifiers, links, code examples, or product/wire constants.

**Domain story**

- `app/lib/domain/CLAUDE.md`
- `app/lib/domain/contracts/dismissed_update_store.dart`
- `app/lib/domain/contracts/update_checker.dart`
- `app/lib/domain/contracts/url_opener.dart`
- `app/lib/domain/value_objects/semver.dart`

**Data/shared story**

- `app/lib/config/CLAUDE.md`
- `app/lib/config/utils/injector.dart`
- `app/lib/data/CLAUDE.md`
- `app/lib/data/update/secure_dismissed_update_store.dart`
- `app/lib/data/update/update_checker_impl.dart`
- `app/lib/data/update/url_launcher_opener.dart`
- `app/lib/pairing/qr_scanner.dart`
- `app/lib/routing/CLAUDE.md`
- `app/lib/routing/adaptive.dart`

**UI story**

- `app/lib/ui/CLAUDE.md`
- `app/lib/ui/chat/widgets/detail_placeholder.dart`
- `app/lib/ui/onboarding/widgets/welcome_step.dart`
- `app/lib/ui/update/states/update_banner_state.dart`
- `app/lib/ui/update/viewmodels/update_banner_viewmodel.dart`
- `app/lib/ui/update/widgets/update_banner.dart`

### Literal review lane (never mechanical)

- `app/lib/domain/entities/update_info.dart` — translate the five Portuguese
  `FormatException` messages while preserving exception type and validation
  branches; translate the surrounding dartdoc/comments in the same review.
- `app/lib/ui/onboarding/widgets/welcome_step.dart` — review the already-EN
  title, description, and CTA together for natural product tone; do not alter
  `Outpost-Pi` or behavior.
- `app/lib/ui/update/widgets/update_banner.dart` — review the already-EN update
  title, version/download line, and dismiss tooltip together; preserve
  interpolation (`v${info.version}`), the `OutpostPi.apk` artifact reference,
  widget keys, and tap/dismiss semantics.

The 16 Dart files plus five layer `CLAUDE.md` files above are the grounded 21
PT-bearing files under `app/lib/`. Tests currently contain no PT-bearing file.

## Always-tier dartdoc audit

The baseline (~278 candidate declarations / ~101 documented / ~177
undocumented) is a broad syntax inventory, not a mandate to document every
public-looking Dart symbol. The following is the reviewed Always-tier gap
manifest. Each listed declaration receives meaningful EN `///` intent/contract
prose; unlisted schema DTOs, constructors, fields, trivial accessors, generated
code, widget `build` overrides, and adapter overrides remain excluded.

### Domain contracts and projections

- `app/lib/domain/contracts/disposable.dart` — `Disposable` and `dispose`.
- `app/lib/domain/contracts/repository.dart` — `Repository` lifecycle marker.
- `app/lib/domain/contracts/service.dart` — `Service` lifecycle marker.
- `app/lib/domain/contracts/usecase.dart` — `UseCase` marker.
- `app/lib/domain/contracts/transcript_event_store.dart` —
  `TranscriptSessionKey`, `AppendTranscriptEventsResult`,
  `TranscriptEventStore`, and its `appendAll`, `readSession`, `watchSession`
  contract methods.
- `app/lib/domain/session_state.dart` — `ChatMessage`, `UserMsg`,
  `AssistantMsg`, `ToolEvent`, `StreamingMessage`, and `AppTurnProjection`.
- `app/lib/domain/transcript/transcript_event.dart` — `TranscriptEvent` plus
  `UserMessageSubmitted`, `UserMessageConfirmed`, `UserMessageFailed`,
  `AssistantDeltaReceived`, `AssistantMessageCommitted`,
  `AssistantDoneReceived`, `ToolRequested`, `ToolFinished`, and
  `CompactionRecorded` (document semantic event role, not fields).
- `app/lib/domain/transcript/transcript_projection.dart` —
  `TranscriptTurnView`, `deriveChatTurnProjection`, and
  `TranscriptProjection`.
- `app/lib/domain/value_objects/reachability.dart` —
  `ReachabilityStateLabel`, `reachabilityBackoffForAttempt`,
  `ReachabilityHeartbeat`, and `ReachabilityTransition`.

`UpdateArtifact` in `app/lib/domain/entities/update_info.dart` remains Skip: it
is a schema-shaped DTO whose fields restate the manifest wire shape. Its
throwing factory behavior is covered by the owning `UpdateInfo` dartdoc.

### Data/service and shared application seams

- `app/lib/config/dependencies.dart` — `setupDependencies`,
  `disposeDependencies`, and `ViewmodelProvider<T>` lifecycle/ownership.
- `app/lib/main.dart` — `reconcileOnAppResume` convergence behavior.
- `app/lib/data/actions/actions_repository.dart` — `IActionsRepository`, its
  `compact`, `newSession`, `setModel`, `setThinking` contracts, and
  `ActionsRepository`.
- `app/lib/data/images/image_picker_service.dart` — `ImagePickerService` and
  `PlatformImagePickerBackend` adapter intent (`ImageSourceKind` is
  self-documenting and excluded).
- `app/lib/data/local/boxes.dart` — public box accessors currently lacking
  docs: `sessionsIndexBox`, `runtimeBox`, `isMsgsBoxOpen`,
  `openTranscriptEventsBox`, `isTranscriptEventsBoxOpen`,
  `transcriptEventsBoxName`, and `sessionKey`.
- `app/lib/data/local/transcript_event_store_hive.dart` —
  `HiveTranscriptEventStore` adapter behavior.
- `app/lib/data/mesh/mesh_sync_service.dart` — `lastVersion` and
  `stopPolling` lifecycle semantics (the service and discriminated results are
  already documented).
- `app/lib/data/preferences/preferences.dart` — persistence semantics for
  `setHideToolCalls`, `setSelectedPeerEpk`, `setOnboardingCompleted`, and
  `setDebugLogging`.
- `app/lib/data/repositories/home_read_repository.dart` —
  `HomeReadRepository`.
- `app/lib/data/repositories/session_read_repository.dart` —
  `SessionReadRepository`.
- `app/lib/data/sync/session_gate.dart` — `SessionGateDecision`, `SessionGate`,
  and `accepts` fail-closed contract.
- `app/lib/data/sync/session_history_replay.dart` —
  `sessionHistoryEventToTranscriptEvent`, `serverReplayEventId`, and
  `serverReplayMessageId` identity contracts.
- `app/lib/data/sync/sync_service.dart` — `SyncService`; stream/snapshot
  getters `streaming`, `streamingStream`, `events`, `queuedText`,
  `queuedStream`, `turnView`, `turnViewStream`, `turnProjection`,
  `turnProjectionStream`, `activeEpk`, `activeRoomId`, `activeSessionRef`; and
  command methods `sendMessage`, `setQueuedMessage`, `clearQueuedMessage`,
  `cancel`, `approveTool`, `requestSync`. Test-only debug seams are excluded.
- `app/lib/data/transport/channel.dart` — document every member of `IChannel`
  and `IControlLink` (ownership, stream meaning, send/close behavior).
- `app/lib/data/transport/connection_manager.dart` — `ConnectionStatus` and
  its five variants, `CancelToken`, `ConnectionManager`; public service seams
  `status`, `statusStream`, `channel`, `roomsSnapshot`, `connectTo`, `adopt`,
  and `disconnect`. Existing documented reachability/room APIs remain as-is;
  test-only debug seams are excluded.
- `app/lib/data/transport/peer_channel.dart` — `PeerChannelError` and
  `PlainPeerChannel`.
- `app/lib/data/transport/relay_config.dart` — `RelaySource`,
  `RelayResolution`, `ConfiguredRelay`, and `UnconfiguredRelay` as the
  explicit configured/unconfigured result contract.
- `app/lib/data/transport/ws_transport.dart` — `WsTransportError`,
  `WsTransport`, `WsInboundFrameKind`, `WsInboundFrameDecision`, and
  `demuxPostAuthInboundFrame` boundary behavior.
- `app/lib/data/voice/speech_service.dart` — `SttResultCallback`,
  `SttLevelCallback`, and the currently-undocumented `SttPlugin`
  `hasPermission`, `stop`, and `cancel` contracts.
- `app/lib/pairing/owner_identity_bridge.dart` — `currentIdentity` lifecycle
  meaning.
- `app/lib/pairing/pair_request_flow.dart` — `PeerTransport` and all three
  methods, `PairingError`, and `performPairing` including its typed throw
  behavior.
- `app/lib/pairing/qr_scanner.dart` — `QrPairPayload`, `tryParse`, and
  `epkBytes` boundary semantics.
- `app/lib/pairing/storage.dart` — `PeerRecord` persistence intent and
  `PairingStorage` methods `savePeer`, `loadPeer`, `deletePeer`, `listPeers`,
  `loadRooms`, and `deleteRooms` that currently lack contract docs.
- `app/lib/routing/adaptive.dart` — `SessionSelection` and its current
  selection lifecycle.

### UI/ViewModel seam

- `app/lib/ui/pairing/viewmodels/pairing_viewmodel.dart` —
  `PairingTransportFactory` and `PairingViewModel`.

All other ViewModel classes already carry purpose-level dartdoc. Public widgets
outside the translation manifest are Recommended, not part of this Always-tier
gap-fill.

## Implementation Units

### Unit 1: Domain translation and contract docs

**Story**: `epic-rebrand-to-outpost-pi-en-first-app-domain`

**Files**: `app/lib/domain/**`

```dart
/// Describe lifecycle ownership and the teardown guarantee.
abstract class Disposable {
  /// Release resources owned by this instance.
  void dispose();
}

/// Describe the canonical append/read/watch transcript contract.
abstract interface class TranscriptEventStore {
  Future<AppendTranscriptEventsResult> appendAll(...);
  Future<List<TranscriptEvent>> readSession(...);
  Stream<List<TranscriptEvent>> watchSession(...);
}
```

**Implementation notes**:
- Translate the five domain PT prose files and the runtime error literals from
  the manifest.
- Write intent/contract docs for the exact domain gap list; do not restate
  constructor fields or duplicate generated/wire schema prose.

**Acceptance criteria**:
- [ ] The six domain-owned PT-bearing files contain natural EN only.
- [ ] All declarations in the domain gap manifest have meaningful `///` docs.
- [ ] The five `FormatException` branches retain their types/conditions and
      expose EN messages.
- [ ] No domain/data/UI import boundary changes occur.

### Unit 2: Data/shared translation and service docs

**Story**: `epic-rebrand-to-outpost-pi-en-first-app-data-shared`

**Files**: `app/lib/config/**`, `app/lib/data/**`, `app/lib/pairing/**`,
`app/lib/routing/**`, and `app/lib/main.dart`

```dart
/// Reconcile authoritative room/session state when the app resumes.
Future<void> reconcileOnAppResume({...});

/// Own the relay connection, retry timers, snapshots, and teardown.
class ConnectionManager extends Service {...}

/// Map a decoded history event into the canonical transcript event stream.
TranscriptEvent sessionHistoryEventToTranscriptEvent(...);
```

**Implementation notes**:
- Translate only the nine fixed PT-bearing files in this ownership slice; the
  remaining files are dartdoc gap-fill only.
- Prefer docs on contracts and lifecycle owners. Adapter overrides inherit
  interface docs unless they add adapter-specific behavior worth recording.

**Acceptance criteria**:
- [ ] The nine owned PT-bearing files contain natural EN only.
- [ ] Every declaration/member in the data/shared gap manifest has meaningful
      `///` documentation without behavior changes.
- [ ] Runtime/wire identifiers, storage keys, URLs, and protocol constants are
      byte-for-byte unchanged.

### Unit 3: UI copy review and ViewModel docs

**Story**: `epic-rebrand-to-outpost-pi-en-first-app-ui-review`

**Files**: `app/lib/ui/**`

```dart
/// Create the transport used for one pairing attempt.
typedef PairingTransportFactory = Future<PeerTransport> Function(...);

/// Drive QR pairing and expose scanning/connecting/paired/error UI state.
class PairingViewModel extends ViewModel<PairingState> {...}
```

**Implementation notes**:
- Translate PT comments/dartdoc in the six fixed UI files.
- Review onboarding and update-banner literals as complete UI phrases. Preserve
  widget keys, interpolation, product identifiers, callback behavior, and
  accessibility tooltip intent.

**Acceptance criteria**:
- [ ] The six UI PT-bearing files contain natural EN only.
- [ ] `PairingTransportFactory` and `PairingViewModel` have intent-level
      dartdoc.
- [ ] Welcome/update copy is reviewed in context and remains natural EN; no
      layout, state, or interaction behavior changes.

## Implementation Order

1. Run the three child stories in parallel; their write paths are disjoint and
   every story has `depends_on: []`.
2. Integrate the three diffs and run the feature-level PT/doc scans.
3. Run formatter check, `flutter analyze`, and `flutter test` once from
   `app/` over the integrated tree.

## Testing

No new production logic is introduced, so the primary evidence is structural
plus the existing behavioral suite.

### Translation checks

From the repository root, scan `app/lib/` for accented Latin characters and
inspect all hits; expected result after implementation is empty:

```bash
grep -RInE '[À-ÖØ-öø-ÿ]' app/lib --include='*.dart' --include='*.md'
```

Then scan comments/docs for common ASCII Portuguese tokens (`para`, `com`,
`sem`, `uma`, `deve`, `quando`, `retorna`, `usuário`, `sessão`) and manually
classify any hits. The implementation must also re-open every file in the
fixed 21-file manifest; a zero accent grep is not sufficient evidence.

### Documentation checks

Apply `.agents/skills/scan-documentation/SKILL.md` to the exact gap manifest:
all listed declarations have adjacent EN `///` intent/contract docs; generated
protocol files, DTO-only declarations, constructors, overrides, tests, and
barrels remain excluded. Run Dart formatting over touched `.dart` files.

### Behavioral gate

From `app/` with the documented writable pub cache and repo Flutter binary:

```bash
export PUB_CACHE=~/projects/remote_pi/.pub-cache
~/projects/remote_pi/.tools/flutter/bin/flutter analyze
~/projects/remote_pi/.tools/flutter/bin/flutter test
```

The existing update-info, semver, update-banner ViewModel, pairing, transcript,
and connection-manager tests are the relevant regression seams. Failures must
be triaged as product bug, test drift, or environment issue; tests must not be
weakened for this prose-only change.

## Risks

- **Riskiest assumption — accented grep equals language detection.** It does
  not. The fixed manifest plus ASCII-token/manual pass is the fallback and the
  completion criterion.
- **Observable strings can be changed accidentally.** Quoted literals are a
  separate review lane; only the five known PT error messages are expected to
  change, while existing EN onboarding/update copy is reviewed, not blindly
  rewritten.
- **Dart public-by-default can turn gap-fill into blanket noise.** The exact
  intent-based manifest prevents documenting generated DTOs, constructors,
  obvious fields, and inherited overrides merely because they are public.
- **Large comment diffs can hide executable edits.** Review `git diff
  --word-diff`/normal diff per story and reject changes to identifiers,
  signatures, control flow, constants, keys, or protocol values.
- **Parallel workers could collide at the integration gate.** Ownership is
  disjoint by path; only the orchestrator runs the final whole-app gate after
  merging all three stories.

## Review (2026-07-15, standard, cross-model fresh-context)

Reviewer: `openai-codex/gpt-5.6-sol` (different model class from the umans
orchestrator). One balanced pass over the integrated feature diff
(`376fa38..HEAD -- app/`).

### Findings
- None. Translation complete; changes are documentation-only except the five
  explicitly scoped English `FormatException` messages. No signature,
  control-flow, wire, or identifier drift.

### Verdict
Approve. Advanced `review → done`.
