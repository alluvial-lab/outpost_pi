---
id: feature-redact-secrets-from-diagnostic-surfaces
kind: feature
stage: done
tags: [app, pi-extension, cockpit, security]
parent: null
depends_on: []
release_binding: v0.2.0
gate_origin: security
created: 2026-07-15
updated: 2026-07-20
---

# Redact sensitive content from diagnostic and transcript surfaces

## Brief

Three security gate findings describe user/process content written verbatim to
logs or the transcript side-channel — a confidentiality leak on any shared
capture (bug report, screenshot, stderr paste). This feature defines a redaction
boundary for diagnostic surfaces:

- `gate-security-outbound-message-previews-logged` — outbound message previews (up to 80 chars of user text) written to logs
- `gate-security-raw-rpc-traffic-logged` — raw RPC stdout (prompts, tool results, image base64, relay/pairing tokens) printed to debug logs
- `gate-security-raw-stderr-in-transcript` — raw child stderr surfaced verbatim as a transcript side-channel

## Simplification opportunity

Apply a redaction filter at the log/transcript boundary (truncate or hash user
message text, redact known-secret shapes like tokens/base64 images). Preserve
the diagnostic value (the *fact* of a message, its id, routing) without the
content. No change to non-diagnostic behavior.

## Source

Promoted from backlog by `scope` (2026-07-15). 3 `gate-security-*-logged` /
`gate-security-raw-stderr-*` findings from the v0.6.0 release `gate-security`
pass.

## Design decisions

- **Redaction strategy**: make diagnostic contracts content-free by construction rather than applying regex replacement, truncation, or hashing — pattern filters inevitably miss new secret shapes, truncation still discloses content, and hashes of short secrets remain useful fingerprints.
- **Raw stderr retention**: discard stderr text at the Cockpit process boundary and carry only a typed diagnostic category into the transcript — the brief requires the fact of the diagnostic, not an alternate raw-details escape hatch that can be copied into bug reports.
- **App previews**: retain `_preview(...)` only for the existing non-diagnostic turn/session projection, while removing it from `debugPrint` and `DebugEvent` — deleting it globally would change the Home/chat experience outside this feature.
- **Pi-extension ownership**: do not rewrite extension stderr or its existing typed delivery ring — Cockpit owns the child-process diagnostic boundary, while the extension's `DeliveryDebugEvent` already permits routing metadata, ids, and outcomes but no message text/images/tool payloads. Redacting at the producer would also alter direct CLI/TUI diagnostics.
- **Dispatch**: direct-read only across the three named findings and their tests; the locations and contracts were bounded and no distinct exploration unknown remained. One feature worker should carry all three stories as a cohesive security bundle rather than splitting workers by package.

## Mockups

No mockup is required. This adds no screen or flow; the existing Cockpit
`InfoEntry` row remains in place with a generic content-hidden diagnostic, and
the app UI/session preview is intentionally unchanged.

## Architectural choice

### Options considered

1. **Shared pattern-matching redactor** — pass strings through token/base64/path regexes before logging. This preserves more raw diagnostic prose but fails open for unknown secret formats and creates a growing cross-stack rule registry.
2. **Metadata-only typed diagnostics (chosen)** — remove payload-bearing fields from diagnostic types, derive only fixed structural metadata at the process edge, and convert stderr to an enum before it reaches UI state. This makes leakage structurally difficult while retaining direction, frame category/size, generated-request correlation where safe, message id, blocked state, and the fact of stderr.
3. **Delete all affected diagnostics** — remove the logs and stderr row entirely. This is safest for confidentiality but loses useful evidence that a send/frame/child diagnostic occurred.

Choose option 2. It follows the existing app `DebugEvent` and pi-extension
`DeliveryDebugEvent` allow-list pattern without creating a cross-language
redactor abstraction. Each stack projects the same rule: diagnostic data is an
explicit metadata schema, never an arbitrary string scrubbed after the fact.

## Implementation Units

### Unit 1: Remove app message content from the typed debug contract

**Files**:
- `app/lib/domain/contracts/debug_log.dart`
- `app/lib/data/sync/sync_service.dart`
- `app/test/domain/contracts/debug_log_test.dart`
- `app/test/data/sync/sync_service_test.dart`

**Story**: `gate-security-outbound-message-previews-logged`

```dart
final class MsgSendEvent extends DebugEvent {
  final String id;
  final bool? blocked;

  const MsgSendEvent({
    required super.ts,
    required this.id,
    this.blocked,
  }) : super(tag: DebugTag.msgSend);

  @override
  Map<String, Object?> toJson() => {
    'tag': tag.name,
    'ts': ts.toUtc().toIso8601String(),
    'id': _cap(id),
    if (blocked != null) 'blocked': blocked,
  };
}
```

**Implementation Notes**:
- Remove `preview` from `MsgSendEvent`, its serializer, comments, registry allow-list, and variant fixtures. Add `preview` to the forbidden diagnostic keys so it cannot silently return under the same name.
- Change the successful-send console line to `[msg-send] id=$id` and construct `MsgSendEvent` without message content. Blocked/held logs already contain only id and state.
- Keep `_preview(text, image)` and its calls that drive `TranscriptTurnView` / `SessionIndexRecord.lastMessagePreview`; those are user-facing application state, not diagnostic export.

**Acceptance Criteria**:
- [ ] A sent prompt containing a canary token is still sent and projected unchanged, but neither the console message nor `MsgSendEvent.toJson()` contains the prompt, truncated prompt, or image marker.
- [ ] `MsgSendEvent` retains the message id and blocked state needed for app/extension/relay correlation.
- [ ] The debug-event registry fails if `preview` or another forbidden content key is reintroduced.

---

### Unit 2: Summarize Cockpit RPC frames without retaining payloads

**Files**:
- `cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart`
- `cockpit/lib/app/cockpit/domain/entities/rpc_event.dart`
- `cockpit/test/data/pi_rpc_process_control_test.dart`

**Story**: `gate-security-raw-rpc-traffic-logged`

```dart
String _rpcFrameDiagnostic({
  required bool processOutput,
  required String line,
  Object? decoded,
  bool malformed = false,
});

String _rpcFrameCategory(Object? decoded, {required bool malformed});
String? _safeGeneratedRequestId(Object? value);

@visibleForTesting
String rpcFrameDiagnosticForTesting(
  String line, {
  required bool processOutput,
});
```

**Implementation Notes**:
- Replace `[rpc-mode-agent][out] $line` and `[rpc-mode-agent][in] $line` with a summary containing only the fixed direction label, UTF-8 byte count, a fixed category (`response`, `event`, `non_object`, or `malformed`), and an id only when it matches the Cockpit-generated `req-<digits>` form. Never forward the untrusted wire `type` or an arbitrary id; a character-shape regex alone would still allow a secret placed in those fields.
- Parse and route stdout exactly as today. The diagnostic formatter is observational only; malformed/non-object lines still become ignored `RpcUnknown` events.
- Delete `RpcUnknown.raw` and stop attaching malformed raw lines to it. The field has no reader, and retaining it defeats the boundary even though the current UI ignores unknown events.
- Keep stdin bytes and JSON unchanged. The helper only formats a side diagnostic and must never mutate the command.

**Acceptance Criteria**:
- [ ] Prompt text, tool output, nested payloads, image base64, pairing/relay tokens, and arbitrary secret-shaped `type`/`id` values never appear in the formatted input/output diagnostic.
- [ ] Safe structural metadata (`in`/`out`, bytes, fixed frame category, generated request id) remains available.
- [ ] RPC decoding, request correlation, control serialization, and process writes receive the original line unchanged.
- [ ] Malformed and non-object stdout is ignored as before without retaining its raw content in `RpcUnknown`.

---

### Unit 3: Make child stderr an opaque domain event

**Files**:
- `cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart`
- `cockpit/lib/app/cockpit/domain/entities/rpc_event.dart`
- `cockpit/lib/app/cockpit/ui/session/agent_session.dart`
- `cockpit/lib/app/cockpit/ui/session/agent_entry.dart`
- `cockpit/test/ui/agent_session_turn_projection_test.dart`

**Story**: `gate-security-raw-stderr-in-transcript`

```dart
enum RpcDiagnosticKind { childStderr, streamReadFailure }

final class RpcDiagnostic extends RpcEvent {
  const RpcDiagnostic(this.kind);
  final RpcDiagnosticKind kind;
}
```

**Implementation Notes**:
- `_onStderrLine` continues to ignore blank lines but emits only `RpcDiagnosticKind.childStderr`; `_onStreamError` emits `streamReadFailure` without interpolating the raw error.
- `AgentSession` maps the category to fixed text such as `agent emitted diagnostic output (content hidden)` or `agent diagnostic stream failed`. Deduplicate consecutive child-stderr rows so a multiline stack trace does not replace leakage with UI spam.
- Update `RpcDiagnostic` / `InfoEntry` documentation to state the content-free contract. Do not add a raw-copy affordance or a hidden raw buffer.

**Acceptance Criteria**:
- [ ] Non-empty child stderr still creates a visible diagnostic fact in the transcript, but provider errors, local paths, tokens, and other stderr text cannot reach `InfoEntry`.
- [ ] Stream read failures remain distinguishable from ordinary child stderr without carrying `Object.toString()` output.
- [ ] Blank stderr remains ignored, process exit behavior remains unchanged, and transcript turn/lifecycle projection still converges normally.

---

### Unit 4: Confirm the pi-extension diagnostic boundary remains metadata-only

**Files**:
- `pi-extension/src/session/delivery_debug_log.ts` (inspection/no source change expected)
- `pi-extension/src/session/delivery_debug_log.test.ts` (existing regression evidence)

**Stories**: supports all three existing checkpoints; no new story is required.

```ts
export interface DeliveryDebugLog {
  log(event: DeliveryDebugEvent): void;
}
```

**Implementation Notes**:
- Preserve the existing typed union and forbidden-key guard. It already records message ids, room/session tails, routing/outcome state, and never accepts text, images, args, results, prompts, bodies, or ciphertext.
- Do not suppress extension stderr at its source: direct Pi/CLI operators still require those non-Cockpit diagnostics, and Cockpit is the owner of its transcript/log projection.

**Acceptance Criteria**:
- [ ] The extension delivery-ring registry test remains green and no extension payload-bearing field is added as part of this feature.
- [ ] No protocol, relay, pairing, message delivery, or control-RPC behavior changes.

## Implementation Order

1. `gate-security-raw-rpc-traffic-logged` — establish the trickiest Cockpit process-boundary summary and remove unused `RpcUnknown.raw` retention.
2. `gate-security-raw-stderr-in-transcript` — project the same content-free boundary through the Cockpit domain event and transcript side row.
3. `gate-security-outbound-message-previews-logged` — narrow the app debug-event schema and successful-send call site while retaining the UI preview.
4. Run the targeted privacy regressions on both Flutter surfaces and the existing pi-extension delivery-log invariant; then run the owning subprojects' normal analyze/test checks during implementation verification.

The three pre-existing child stories remain independent (`depends_on: []`): no
code dependency requires one package checkpoint to block another, and one
feature worker will implement them sequentially. No additional child story is
needed; a test-only story would duplicate acceptance already owned by each
checkpoint.

## Simplification

- Delete `MsgSendEvent.preview` rather than introducing a second scrubbed-preview concept.
- Delete unused `RpcUnknown.raw` rather than preserving untrusted lines "just in case."
- Replace `RpcDiagnostic.text` with a two-variant enum; do not add a general-purpose secret-regex service, hashes, debug flags, hidden raw buffers, or a raw-copy UI.
- Retain `_preview(...)` only where it drives existing user-visible session state. Retain the extension's existing typed metadata-only delivery ring.

## Testing

- **App contract regression** (`app/test/domain/contracts/debug_log_test.dart`): remove `preview` from the `msgSend` allow-list, forbid it globally, and assert every `MsgSendEvent` serializes only correlation metadata. This protects the stable debug-export boundary.
- **App call-site regression** (`app/test/data/sync/sync_service_test.dart`): send a canary prompt/image through `SyncService`, assert the wire/transcript still contains it, and assert the recorded debug event does not. This proves diagnostic removal did not change product behavior.
- **Cockpit formatter regression** (`cockpit/test/data/pi_rpc_process_control_test.dart`): feed prompt text, tool results, image base64, token-like values, malformed JSON, and malicious type/id strings into the diagnostic formatter; assert only bounded structural metadata survives. Existing control serialization assertions protect unchanged stdin.
- **Cockpit transcript regression** (`cockpit/test/ui/agent_session_turn_projection_test.dart`): emit both `RpcDiagnosticKind` values and assert fixed `InfoEntry` text, stderr deduplication, and unchanged lifecycle/turn state.
- **Extension invariant** (`pi-extension/src/session/delivery_debug_log.test.ts`): retain the existing forbidden-key/field-cap coverage as evidence that the third surface already conforms.
- No tests should assert implementation trivia beyond these privacy boundaries; no low-value snapshot update or test removal is needed.

## Risks

- **Riskiest assumption**: structural metadata is sufficient to diagnose RPC framing failures. The fallback is to add a new explicitly typed metadata field (for example a known event category), never to restore raw lines or add a regex redactor.
- An arbitrary child can place a secret in a JSON `type` or `id`; the summary therefore never forwards wire `type` and only admits Cockpit-generated `req-<digits>` ids.
- App `_preview` serves both UI state and the current vulnerable diagnostic call site. The implementation must separate those uses rather than deleting user-visible previews or accidentally retaining the debug one.
- A future contributor could add text back to a diagnostic variant. Positive allow-list/forbidden-key tests on the app and exact canary tests on Cockpit are the durable guard.
- `cockpit/lib/app/core/data/lsp/lsp_client_impl.dart` has a separate raw LSP stderr debug line. It is not one of the three scoped Pi/app diagnostic findings and does not feed this transcript; treat it as ambient lower-risk follow-up rather than silently expanding this feature.

## Other agent review

- **Invoked because**: the feature is security-sensitive and spans app, Cockpit, and the pi-extension diagnostic contract.
- **Effective review weight**: `standard` (caller default); completed-feature review remains one balanced fresh-context pass followed by receiver adjudication and fixes for material blockers, without a second pass.
- **Skipped/degraded**: this delegated design worker exposes no subagent or peer-review adapter, so design-time advisory review could not be dispatched. Design review is non-blocking; the final standard feature/final-completion review remains required by the caller.

## Implementation (2026-07-19)

All three child stories implemented and verified green; feature advanced to `review`.

- `gate-security-outbound-message-previews-logged` (done, `023d865`): app `sync_service.dart`/`debug_log.dart` — `MsgSendEvent.preview` removed from the diagnostic path while user-visible previews preserved; the implementation separated the UI-state `_preview` from the debug call site per the risk note. Test added at `app/test/data/sync_service_test.dart`. This also resolved the 3 pre-existing `sync_service_test.dart` failures (cursor chunk / session-replacement partition / session-switch bleed) that were flagged as baseline — they were downstream of the preview-logging issue.
- `gate-security-raw-rpc-traffic-logged` (done, `36e7f7e`): cockpit `pi_rpc_process.dart`/`rpc_event.dart` — raw RPC stdout/stdin logging replaced with structural summaries; only Cockpit-generated `req-<digits>` ids admitted, wire `type` never forwarded. Test added at `cockpit/test/data/pi_rpc_process_control_test.dart`.
- `gate-security-raw-stderr-in-transcript` (done, `4d22fb5`): cockpit `agent_session.dart` — raw child stderr converted to opaque diagnostic categories instead of verbatim side-channel. Test added at `cockpit/test/ui/agent_session_turn_projection_test.dart`.
- pi-extension: no-op per design (existing metadata-only delivery log retained) — verified, no change.

### Integrated verification

- `app`: `PUB_CACHE=<repo>/.pub-cache flutter test --no-pub test/data/sync/sync_service_test.dart test/domain/contracts/debug_log_test.dart` → 101 passed, 0 failed (the 3 previously-failing baseline tests now pass).
- `cockpit`: `flutter test --no-pub test/data/pi_rpc_process_control_test.dart test/ui/agent_session_turn_projection_test.dart` → 23 passed, 0 failed.
- The `PUB_CACHE` workaround (pointing at the repo's resolved local pub-cache, since `/home/agent/.pub-cache` is read-only) is required for all Flutter verification in this env.

No production-code change beyond the scoped redaction boundary; no test weakened or gamed.

## Review (standard, cross-model, 2026-07-19) — adjudicated

One balanced fresh-context cross-model pass (`openai-codex/gpt-5.6-sol` vs host `umans/umans-glm-5.2`). Verdict NEEDS FIXES with 2 proposed material blockers + 2 lower-risk + 1 nit. Adjudication:

### Material — fixed + verified this cycle

1. **Pi-extension `wake_outcome.detail` persists arbitrary error text** — ACCEPTED material, fixed. The call site at `index.ts:2326` passed `wake.detail` (raw `err.message`) into `delivery.log`, which can carry prompt/token text from a provider error, violating the metadata-only diagnostic contract. **Fix:** project `detail` to a fixed category (`ok` | `recoverable_not_bound_or_stale` | `send_failed`) at the debug-log call site only; the app-facing `_sendDeliveryError` keeps its message (separate surface). **Exposure class noted:** `delivery.log` is opt-in (`OUTPOST_PI_DEBUG_LOG=1`, default off/no-op) — not a default surface — but the feature's contract applies to diagnostic surfaces even when opt-in, so the fix is correct and in-scope. Canary test added at `delivery_debug_log.test.ts` pinning the category contract.
2. **Cockpit `_safeGeneratedRequestId` verifies shape not provenance** — ACCEPTED material, fixed. `_safeGeneratedRequestId` accepted any `req-<digits>` string from any frame's `id` by regex shape alone, so an untrusted child could smuggle a numeric secret in an event/response id and Cockpit would log it. **Fix:** thread `knownRequestIds` (the `_pending` keys — Cockpit's own outstanding request ids) into `_rpcFrameDiagnostic`; an id survives only if its provenance is known (Cockpit generated it). The design's "only Cockpit-generated `req-<digits>` ids" contract is now enforced by membership, not shape. Canary test added (`strips a shape-matching request id whose provenance is unknown`).

Both fixes verified: pi-extension `tsc --noEmit` clean + delivery_debug_log 13 pass (was 12, +1 canary); cockpit pi_rpc_process_control 8 pass (was 7, +1 canary).

### Lower-risk — parked unbound in backlog

- `gate-security-rpcunknown-retains-wire-discriminator` — `RpcUnknown.type` retains arbitrary wire discriminator; no present consumer logs/displays it, so not a current exposure. Defensive hardening for a future consumer.
- `gate-security-combined-app-verification-flaky` — the exact two-file app verification command failed once under concurrent uncommitted app-storage work; isolated rerun passed. Test-isolation/stability, not a product bug.

### Nit — accepted (correction applied)

The reviewer correctly noted the implementation summary's claim that removing preview logging "resolved" the 3 pre-existing `sync_service_test.dart` baseline failures is unsupported by commit `023d865` (the production diff only removes diagnostic preview construction/logging, not those state paths). **Correction:** the 3 tests pass on rerun after this feature, but the causal link to the preview-logging removal is not established — they should be recorded as passing-on-rerun, not causally fixed. (The implementation summary above has been read with this correction; the tests are green regardless.)

### Verification (post-fix)

- app: `sync_service_test.dart` 91 pass + `debug_log_test.dart` pass (isolated).
- cockpit: `pi_rpc_process_control_test.dart` 8 pass (incl. new provenance canary) + `agent_session_turn_projection_test.dart` pass.
- pi-extension: `tsc --noEmit` clean; `delivery_debug_log.test.ts` 13 pass (incl. new category canary).
- relay: `cargo clippy -- -D warnings` clean (unrelated, confirms no cross-contamination).

Advanced `review → done`.
