---
id: story-e2e-oddities-failure
kind: story
stage: done
tags: [app, testing]
parent: feature-e2e-live-oddities-suite
depends_on: [story-e2e-oddities-harness-infra]
release_binding: v0.7.0
gate_origin: null
created: 2026-08-21
updated: 2026-08-21
---

# Failure-mode device tests incl. the parked-oddity regression scenarios

Invariant 1 (no silent message loss) and the failure faces of 2/3. Scenarios
for KNOWN-OPEN bugs assert the correct behavior and are marked skip/xfail
linked to the tracking id — flipped when the fix lands. Never weaken the
assertion to pass; never delete a flaky scenario without root-causing.

## Units

### Unit 1: `app/integration_test/live_failure_test.dart` (e2e-tagged)
1. **Swallow regression** (*xfail → story-app-send-swallowed-session-
   identity-unavailable*): reconnect via net_fault → on StatusOnline+
   hydrate, send immediately (the 63s identity window) → assert the message
   is visible (pending/delivered/visually failed) — never absent.
2. **Blank-chat regression** (*xfail → backlog-app-blank-chat-direct-open*):
   cold start directly into the session route → assert history renders
   without backing out.
3. **Offline send**: airplane on → send → visible pending; airplane off →
   resent → delivered (or visibly failed at the 20s bound).
4. **Pair with relay down**: relay paused → pair attempt → visible failure
   state (no hang); relay resumed → pair succeeds.
5. **Extension restart mid-conversation**: `/__restart` → next send →
   delivered; no prior-message loss (transcript intact).

## Acceptance criteria
- [x] 3 fully-green scenarios + 2 xfail-linked ones (ids cited in-code),
      via `e2e/run-live.sh`, stable across two runs.
- [x] Each scenario's invariant stated in a doc comment.
- [x] When the swallow fix lands, flipping its xfail is part of that fix
      story's verification (recorded there).

## Implementation

- Execution capability: `sol/high` — real-device failure regressions with relay, owner-channel, persistence, and process restart boundaries.
- Review weight: standard (project default); review is not applicable to this child-story checkpoint.
- Added `app/integration_test/live_failure_test.dart` with five invariant-documented scenarios. The swallow and blank-chat scenarios retain full correct-behavior assertions and `skip: true` notes naming `story-app-send-swallowed-session-identity-unavailable` and `backlog-app-blank-chat-direct-open`; their fix stories remove only the skip.
- Invariant mapping: offline send asserts the rendered pending bubble, transcript status, and `sendQueue` held/resend events; relay-down pairing asserts visible bounded failure then successful retry; preserving pi-host restart asserts the post-restart rendered turn and all pre/post rows in the transcript DB.
- The emulator's adb-reversed localhost remains reachable under Android airplane mode, so the runner mirrors the radio cut at Toxiproxy while still applying the real adb airplane toggle.
- The live pi-host now starts relay-only (the local UDS mesh is outside this lane), gracefully leaves before a preserving respawn, continues the recent SDK session, and delays the special respawn long enough to retain stable room/session identity. This removes adapter-generated room rotation without changing production extension behavior.
- The restart scenario exposed a real app convergence gap: `PeerWentOffline` remained sticky after the room was live again. `ChatViewModel` now clears that reason on online/authoritative live-room convergence while room liveness independently keeps input fail-closed.
- The attachment provider uses a static empty model catalogue in this chat-only harness so unrelated quick-action catalogue requests cannot become unhandled disconnect errors during deliberate network faults; pairing, transport, sync, persistence, and chat rendering remain production implementations.
- Files changed: `app/integration_test/live_failure_test.dart`, `app/integration_test/support/live_device_harness.dart`, `app/lib/ui/chat/viewmodels/chat_viewmodel.dart`, `e2e/run-live.sh`, `e2e/services/pi-host.Dockerfile`, `pi-extension/src/extension/testing.ts`, `pi-extension/src/index.ts`, `pi-extension/test/support/e2e_pi_host_server.ts`, `pi-extension/test/support/e2e_pi_host_runtime.ts`, and this item.
- Tests added: five e2e-tagged device scenarios (three green, two correctly skipped known-open regressions).
- Simplification: one allow-listed fault-marker loop drives every repeated fault; the restart adapter uses the SDK's existing `continueRecent` and relay-only test seam rather than custom transcript restoration.
- Discrepancies from design: the preserving `/__restart` adapter initially minted a fresh SDK session and a broker-collision room; the adapter was corrected to model the supervised production restart contract before asserting history retention.
- Adjacent issues parked: none.

Verification (2026-08-21):

```text
# consecutive run 1 tail
00:42 +3 ~2: All tests passed!
live device e2e passed: integration_test/live_failure_test.dart + capture

# consecutive run 2 tail
00:44 +3 ~2: All tests passed!
live device e2e passed: integration_test/live_failure_test.dart + capture

flutter analyze
No issues found!
```

### Review closure

- The swallow regression now waits for capture-ring proof of the online route
  state without canonical session identity before sending, then requires both
  the rendered bubble and transcript-DB row. It remains skip-linked to
  `story-app-send-swallowed-session-identity-unavailable`.
- The blank-chat regression restores the persisted pair and mounts the direct
  chat route only after `run-live.sh` force-stops the preceding app process. It
  remains skip-linked to `backlog-app-blank-chat-direct-open`.
- Review-closure device run: three scenarios green in `failure-main`; both known
  regressions remained linked/skipped, and the force-stopped `blank-cold` phase
  relaunched cleanly with the cold regression still explicitly skipped.
