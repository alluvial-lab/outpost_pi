---
id: feature-diagnostic-privacy-hardening
kind: feature
stage: done
tags: [security, cockpit, app]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: security
created: 2026-07-23
updated: 2026-07-24
---

# Diagnostic-privacy hardening (round 2)

## Brief

Follow-up cluster to 0.2.0's `feature-redact-secrets-from-diagnostic-surfaces`.
The 2026-07-23 groom verified these five findings are **not** superseded by
the shipped redaction work — live code still leaks raw diagnostic content into
logs, traces, and retained events:

1. `gate-security-cockpit-temp-workspace-trace` — temp workspace's absolute
   path in traces.
2. `gate-security-formatter-reload-diagnostics-path-disclosure` — raw file
   exception and full stack trace in diagnostics.
3. `gate-security-lsp-stderr-logged` — LSP stderr lines logged verbatim.
4. `gate-security-mobile-failure-detail-logged` — mobile failure detail
   written verbatim into a persistent exportable `MsgFailedEvent`.
5. `gate-security-rpcunknown-retains-wire-discriminator` — unknown-RPC
   handling retains arbitrary wire discriminator text.

Each finding carries severity/location/evidence/remediation in its child
story. The design pass should establish one shared diagnostic-redaction
policy (what may be logged verbatim, what is hashed/truncated, what is
redacted) rather than five point fixes — that policy is the feature's real
deliverable; the child stories are its applications.

## Simplification opportunity

A single redaction helper/policy module per subproject (extending the 0.2.0
`feature-redact-secrets-from-diagnostic-surfaces` seams) replaces per-callsite
ad-hoc redaction and gives future diagnostics a default-safe path.

## Origin

Groom 2026-07-23, cluster F6 — promoted per advisor-review recommendation
that diagnostic-privacy follow-ups pair with v0.3.0 hardening.

## Design decisions

- **Shared policy = the 0.2.0 policy, adopted verbatim**: diagnostic surfaces
  are content-free BY CONSTRUCTION — fixed categories and closed code sets
  projected at each boundary, never arbitrary strings scrubbed after the fact
  (no regex redactor, no truncation-as-redaction, no hashing). The 0.2.0
  feature body (`releases/v0.2.0/feature-redact-secrets-from-diagnostic-surfaces.md`)
  already settled this; this feature applies it to the five remaining surfaces.
- **No new redactor module**: the brief's "single helper/policy module per
  subproject" is rejected as over-abstraction. The app already HAS the policy
  module (`app/lib/domain/contracts/debug_log.dart` — DebugTag enum as capture
  surface, sealed variants, forbidden-keys registry test); it gets tightened,
  not duplicated. Cockpit has no registry and needs none — 0.2.0 established
  per-site fixed categories there (`RpcUnknown('<parse-error>')` convention).
  The shared element is the POLICY + test enforcement, not a runtime helper.
- **Projection boundary owns redaction, not the producer**: no pi-extension
  change. The wire may carry raw error text (owner channel, E2E-sealed);
  each app/cockpit surface projects it content-free at capture. Consistent
  with the 0.2.0 extension decision.
- **User-visible transcript error text retained**: `UserMessageFailed.message`
  is product UX (the user sees why THEIR message failed, stored in their
  encrypted transcript) — explicitly out of diagnostic scope per the finding's
  own remediation. Only the exportable diagnostic surfaces (`debugPrint`,
  `MsgFailedEvent`) go content-free.
- **`SessionSyncEvent.err` folded into the mobile story**: identical leak
  shape in the same contract file (`sync_service.dart:647` passes
  `_shortReason(err)` from an arbitrary Object). Fixing only `MsgFailedEvent`
  would leave the same hole one field away; the registry tightening covers both.
- **Wire `code` admitted by membership, not shape**: `errorCode` is an OPEN
  string in the schema ("receivers tolerate future values"), so a wire `code`
  is untrusted text. Diagnostics admit only a closed set (protocol
  `knownErrorCode` + app-local codes) and project anything else to a fixed
  `unrecognized` category. `knownErrorCode` is NOT generated into Dart, so the
  set is one handwritten const tied to the schema by comment.
- **Cockpit `RpcUnknown` keeps fixed-category strings**: `.type` has no reader
  (`agent_session.dart:740` ignores the event), but the field documents mapper
  decision points and matches the existing `'<parse-error>'` style. The fix is
  replacing the 4 ARBITRARY interpolations with fixed categories, not deleting
  the field.
- **LSP stderr keeps structural metadata only**: cockpit-owned `languageId`,
  non-empty line count, and exit code are bounded structural facts; raw lines
  and error strings are discarded. No raw opt-in is built — the fallback if
  debugging needs more is a NEW explicitly-typed field, never raw text.

## Architectural choice

### Options considered

1. **Per-subproject redactor/scrubber module** (the brief's simplification
   sketch) — one helper that filters strings before capture. Rejected: 0.2.0
   already chose content-free-by-construction over scrubbing; a scrubber fails
   open for unknown secret shapes and becomes a growing rule registry.
2. **Tighten the existing app policy module + per-site fixed categories in
   cockpit (chosen)** — extend `debug_log.dart`'s invariant (forbidden keys
   `detail`/`err`, closed-code admission), delete the app's dead
   `debugDetail`/`_shortReason` machinery, and give each cockpit boundary a
   fixed category matching the established `'<<em>category</em>>'` convention.
3. **Delete the five diagnostics outright** — safest but loses the FACT of a
   failure (send failure with code, LSP stderr occurrence with count, reload
   failure with error class), which real debugging uses.

Choose option 2. It finishes the job 0.2.0 started with the smallest possible
surface: one tightened contract file, five projected call sites, canary tests.

## Implementation Units

### Unit 1: Close the app failure-diagnostic content hole (trickiest — designed first)

**Files**:
- `app/lib/domain/contracts/debug_log.dart`
- `app/lib/data/sync/sync_service.dart`
- `app/test/domain/contracts/debug_log_test.dart`
- `app/test/data/sync/sync_service_test.dart`

**Story**: `gate-security-mobile-failure-detail-logged`

```dart
/// Closed set of failure codes admissible into diagnostics: protocol
/// `knownErrorCode` (schema: defs/app-pi-common.schema.json — NOT generated
/// into Dart; keep in sync by hand) plus app-local codes. Open-string wire
/// codes outside this set project to [kUnrecognizedFailureCode].
const Set<String> kAdmissibleFailureCodes = {
  // protocol knownErrorCode
  'tool_approval_required', 'invalid_message', 'unsupported_type',
  'too_large', 'rate_limited', 'timeout', 'internal_error',
  'session_mismatch', 'delivery_pending',
  // app-local
  'send_error', 'send_timeout', 'cancelled',
};
const String kUnrecognizedFailureCode = 'unrecognized';

String admitFailureCode(String wireCode) =>
    kAdmissibleFailureCodes.contains(wireCode)
        ? wireCode
        : kUnrecognizedFailureCode;
```

**Implementation Notes**:
- `MsgFailedEvent`: DELETE the `detail` field and its serializer entry; keep
  `id` and `code`. `SessionSyncEvent`: DELETE the `err` field entirely (the
  event retains the FACT of a sync failure + timestamp).
- Extend the class doc invariant: "no variant carries server-originated or
  arbitrary error text; failure diagnostics admit only closed code sets or
  fixed categories." Add `detail` and `err` to the registry test's forbidden
  keys so capped-arbitrary-string fields cannot return under those names.
- `sync_service.dart` `_failPendingSend`: console line becomes
  `'[msg-failed] id=$id code=${admitFailureCode(code)}'`; `MsgFailedEvent`
  constructed without `detail`, `code` admitted via `admitFailureCode`.
- DELETE the now-dead `debugDetail` parameter from `_failPendingSend` (both
  call-site arguments), and DELETE `_shortReason` (its only other consumer was
  `SessionSyncEvent.err`). Deletion, not retention — capped arbitrary text is
  still arbitrary text.
- `UserMessageFailed(code:, message:)` transcript append is UNCHANGED
  (user-visible product state).

**Acceptance Criteria**:
- [ ] Canary: a server `error` frame whose `message` embeds a secret-shaped
  string (path/token/prompt fragment) rejects a pending send; the recorded
  `MsgFailedEvent.toJson()` and console capture contain neither the secret
  nor any substring of it, while `code` survives when known (`internal_error`)
  and projects to `unrecognized` when not.
- [ ] `UserMessageFailed` transcript projection still carries the raw
  user-visible message (product behavior unchanged).
- [ ] Registry test fails if `detail`, `err`, or another content key is
  reintroduced on any variant.
- [ ] `debugDetail` parameter and `_shortReason` are gone; analyzer clean.

---

### Unit 2: Fixed unknown categories at the cockpit RPC mapper boundary

**Files**:
- `cockpit/lib/app/cockpit/data/adapters/rpc_event_mapper.dart`
- `cockpit/test/data/adapters/rpc_event_mapper_test.dart` (or its existing home)

**Story**: `gate-security-rpcunknown-retains-wire-discriminator`

**Implementation Notes**:
- Replace exactly four arbitrary interpolations with fixed categories in the
  established angle-bracket convention: `:79` → `const RpcUnknown('<unknown-frame>')`;
  `:162` → `'<unknown-custom-message>'`; `:234` → `'<unknown-ui-request>'`;
  `:276` → `'<unknown-message-update>'`. All other `RpcUnknown` constructions
  are already fixed strings — leave them.
- Do NOT delete the `type` field (documents mapper decision points; no reader
  exists, so fixed strings are harmless).

**Acceptance Criteria**:
- [ ] Canary: frames with secret-shaped `type`/`customType`/`method`/
  `eventType` map to `RpcUnknown` whose `type` is the fixed category and
  contains no substring of the secret.
- [ ] Known frames route exactly as before (existing mapper tests green).

---

### Unit 3: LSP stderr becomes counted, content-free diagnostics

**Files**:
- `cockpit/lib/app/core/data/lsp/lsp_client_impl.dart`
- `cockpit/test/core/data/lsp/lsp_client_impl_test.dart` (or its existing home)

**Story**: `gate-security-lsp-stderr-logged`

**Implementation Notes**:
- `_onStderrLine`: ignore blank lines as today; count non-empty lines in a
  `_stderrLineCount` field; emit ONE content-free line per process
  (`[lsp:<languageId>][err] server diagnostic output (content hidden)`) on
  first occurrence — no line content, ever.
- `_onStreamError`: `[lsp:<languageId>] stream error (content hidden)` — drop
  the `$error` interpolation.
- `_onExit`: include `stderrLines=N` alongside the exit code (both bounded
  structural metadata). `languageId` is cockpit-owned config, safe to log.

**Acceptance Criteria**:
- [ ] Canary: stderr lines embedding absolute paths/source excerpts never
  appear in captured debug output; the count and exit code survive.
- [ ] Blank-line skipping, request/response handling, and exit behavior are
  unchanged.

---

### Unit 4: Formatter-reload failure becomes a fixed category + error class

**Files**:
- `cockpit/lib/app/cockpit/ui/widgets/file_viewer.dart`
- `cockpit/test/ui/widgets/file_viewer_test.dart` (or its existing home)

**Story**: `gate-security-formatter-reload-diagnostics-path-disclosure`

**Implementation Notes**:
- Replace `debugPrint('[file-viewer] _reloadFromDisk failed: $e\n$st')` with
  `debugPrint('[file-viewer] reload-from-disk failed (${e.runtimeType})')`.
  Dart `runtimeType` names are compile-time fixed — no paths, no content, no
  stack trace.

**Acceptance Criteria**:
- [ ] Canary: a `FileSystemException` carrying an absolute path triggers the
  catch; captured output contains the error class but no path and no stack.
- [ ] The reload fallback (no buffer change on failure) is unchanged.

---

### Unit 5: Delete the ck_trace temporary crash marker

**Files**:
- `cockpit/lib/app/cockpit/ui/cockpit_page.dart`

**Story**: `gate-security-cockpit-temp-workspace-trace`

**Implementation Notes**:
- Delete `_mark`, all its call sites, and the `dart:io` import IF it becomes
  unused (line 448's `vm.openFile` is NOT dart:io — verify before removing).
  Pure deletion: the Windows crash investigation it served is closed.

**Acceptance Criteria**:
- [ ] No `ck_trace.log` reference remains; Create Workspace flow behavior and
  its existing tests are unchanged.

## Implementation Order

1. `gate-security-mobile-failure-detail-logged` — trickiest: user-visible vs
   diagnostic separation, closed-code admission, registry tightening.
2. `gate-security-rpcunknown-retains-wire-discriminator` — 4 site substitutions.
3. `gate-security-lsp-stderr-logged` — counted content-free projection.
4. `gate-security-formatter-reload-diagnostics-path-disclosure` — one line.
5. `gate-security-cockpit-temp-workspace-trace` — pure deletion.

The five pre-existing child stories stay independent (`depends_on: []`): no
code dependency orders them, and one feature worker carries them sequentially
as checkpoints. No new stories are spawned — the children already exist and
the design maps onto them; only the mobile story's scope is widened
(SessionSyncEvent.err + registry tightening, recorded in its body).

## Simplification

- Delete `MsgFailedEvent.detail`, `SessionSyncEvent.err`, `_failPendingSend`'s
  `debugDetail` parameter, and `_shortReason` — removing the whole
  capped-arbitrary-string channel rather than filtering it.
- Delete the `_mark` temp-trace machinery outright (no debug-gated retention).
- No new abstraction: the policy is enforced by the existing registry test +
  per-boundary canary tests.

## Testing

- **App registry regression** (`debug_log_test.dart`): forbidden keys extended
  with `detail`/`err` — protects the exportable-diagnostic contract boundary.
- **App wire→diagnostic canary** (`sync_service_test.dart`): server error with
  secret-shaped message; transcript keeps it, diagnostics don't — protects the
  user-visible/diagnostic separation this design hinges on.
- **Cockpit mapper canary**: secret-shaped discriminators never reach
  `RpcUnknown.type`.
- **Cockpit LSP canary**: path-bearing stderr lines never reach debug output;
  count + exit code survive.
- **Cockpit file-viewer canary**: path-bearing exception → class only.
- No test for the ck_trace deletion; existing Create Workspace tests protect
  behavior. No snapshots, no per-branch coverage.

## Risks

- **Riskiest assumption**: fixed categories + codes + counts retain enough
  diagnostic value for real failure debugging. Fallback if not: add a NEW
  explicitly-typed metadata field (never restore raw text, never a regex
  redactor) — same escape hatch 0.2.0 recorded.
- `kAdmissibleFailureCodes` is handwritten (knownErrorCode is not generated
  into Dart) and could drift from the schema — mitigated by the comment tie;
  the release `scan-protocol-contract` gate is the systemic catch.
- `SessionSyncEvent` loses its only cause hint — accepted: the fact + ts plus
  neighboring correlation events suffice today; typed category can be added
  later if a real debugging need appears.
- LSP server misconfiguration becomes less visible without stderr text —
  mitigated by exit code + line count; a local debug opt-in can be designed
  later if operators actually need it (not built speculatively).

## Implementation (2026-07-23)

All five child stories implemented by one feature worker (Terra/high), each
verified and committed; feature advanced to `review`.

- `gate-security-mobile-failure-detail-logged` (done, `1480ecc` + follow-up
  `97d8b84`): `kAdmissibleFailureCodes`/`admitFailureCode` landed in
  `debug_log.dart`; `MsgFailedEvent.detail`, `SessionSyncEvent.err`,
  `_failPendingSend.debugDetail`, and `_shortReason` all deleted; registry
  forbidden keys extended; wire→diagnostic canary proves user-visible
  `UserMessageFailed.message` retained while console/ring stay content-free.
  Orchestrator wave inspection caught the sibling `[session-sync] ... $err`
  console leak in the same function — fixed content-free in the follow-up.
- `gate-security-rpcunknown-retains-wire-discriminator` (done, `8798c41`):
  4 arbitrary interpolations → fixed `'<unknown-*>'` categories; mapper canary.
- `gate-security-lsp-stderr-logged` (done, `9e5302c`): counted content-free
  stderr (first-occurrence line), stream-error category, exit code +
  `stderrLines=N`; real-subprocess canary.
- `gate-security-formatter-reload-diagnostics-path-disclosure` (done,
  `46e2e1a`): `fileViewerReloadFailureDiagnostic` (class only, `@visibleForTesting`);
  path-bearing-exception canary.
- `gate-security-cockpit-temp-workspace-trace` (done, `e777716`): `_mark`,
  call sites, and unused `dart:io` import deleted.

### Integrated verification (orchestrator, post-wave)

- `app`: `flutter analyze` clean; `flutter test` 816 passed, only the 6 known
  pairing-endpoint e2e environment failures (unchanged baseline).
- `cockpit`: `flutter analyze` clean (after `73a3fe8` fixed the pre-existing
  `unnecessary_underscores` lint at `pi_rpc_process.dart:470` that had blocked
  the worker's transition); `flutter test` 261/261 passed.

## Review (standard, cross-model, 2026-07-23) — adjudicated, closed

One balanced fresh-context cross-model pass (`openai-codex/gpt-5.6-sol` vs host
`umans/umans-glm-5.2`). Verdict REQUEST CHANGES with 2 proposed blockers + 2
important, 0 nits. Adjudication:

### Material — fixed + verified this cycle (`82ddbb9`)

1. **Pre-upgrade sensitive ring entries remain exportable** — ACCEPTED
   material, fixed. `_doLoad()`/`export()` in `debug_log_impl.dart` retained
   and returned legacy JSONL lines unchanged, so pre-upgrade
   `MsgFailedEvent.detail` / `SessionSyncEvent.err` (and 0.2.0-era `preview`)
   rows survived the upgrade and could still egress on export. Fix: promoted
   the forbidden-key set to production `kForbiddenDiagnosticKeys`
   (single-sourced with the registry test) and drop any line carrying a
   forbidden key at BOTH egress boundaries (ring load + export) — discard, not
   scrub, per policy. Seeded legacy-row export canary added.
2. **Held-message resend logs arbitrary exception content** — ACCEPTED
   material, fixed. `sync_service.dart:828` printed `failed: $err` from
   `_resendHeldPendingMessages`; a persistence/transport exception can carry
   paths/tokens. Fix: fixed-category console line + secret-shaped
   resend-failure console canary.

### Important — one fixed, one parked

3. **`MsgFailedEvent.code` accepted any String** (capture surface not closed
   by construction) — fixed in the same commit: the constructor now normalizes
   through `admitFailureCode`, so admission is enforced by the type, not by
   caller discipline.
4. **Three canaries don't drive their production capture branch**
   (file-viewer helper-only, session-sync keys-only, LSP onError uncovered) —
   PARKED unbound as `idea-privacy-canaries-production-boundary-coverage` with
   risk rationale: all three call sites are now fixed strings with no
   interpolation; exposure requires a future edit re-introducing it, and the
   shared pattern is covered by this cycle's other canaries.

### Verification (post-fix)

`flutter analyze` clean; full `flutter test` 818 passed (+2 net new canaries),
only the 6 known pairing-endpoint e2e environment failures. Cockpit untouched
by the fixes (261/261 from wave verification stands).

Closure: `standard` weight — one independent pass, receiver-confirmed blockers
fixed and verified, no second pass. Advanced `review → done`.
