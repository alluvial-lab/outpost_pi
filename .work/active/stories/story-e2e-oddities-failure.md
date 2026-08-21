---
id: story-e2e-oddities-failure
kind: story
stage: implementing
tags: [app, testing]
parent: feature-e2e-live-oddities-suite
depends_on: [story-e2e-oddities-harness-infra]
release_binding: null
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
- [ ] 3 fully-green scenarios + 2 xfail-linked ones (ids cited in-code),
      via `e2e/run-live.sh`, stable across two runs.
- [ ] Each scenario's invariant stated in a doc comment.
- [ ] When the swallow fix lands, flipping its xfail is part of that fix
      story's verification (recorded there).
