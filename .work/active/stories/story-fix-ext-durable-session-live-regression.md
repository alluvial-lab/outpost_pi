---
id: story-fix-ext-durable-session-live-regression
kind: story
stage: done
tags: [bug, pi-extension]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: null
created: 2026-08-25
updated: 2026-08-25
---

# Preserve durable transcript writes after live session replacement

## Symptom

`e2e/run-live.sh state-shapes` failed 3/3 after the durable-transcript arc. Live app sends reached the real SDK turn boundary, but after `session_new` the extension emitted no durable transcript entries, user echo, assistant reply, or useful replay events; the app eventually marked the send `send_timeout`. Soak seed `20260901` showed the same multi-session failure and a late old-session `action_ok` correctly rejected by the app session gate.

## Root cause

`SdkSessionProjection.bindReplacementContext()` replaced message/action capabilities from Pi's fresh `withSession` context and also cleared transcript persistence when that context lacked `appendEntry`. Real `ReplacedSessionContext` carries message delivery methods but not the factory `ExtensionAPI.appendEntry` writer. The preceding fresh `session_start` had already rebound the correct current-session factory writer, but the later `withSession` callback discarded it. Durable-first visibility then correctly suppressed every transcript projection because persistence was unavailable.

## Fix approach

Keep transcript-writer ownership on the `session_start`/factory lifecycle. A replacement context may replace message and action capabilities and may provide a newer writer when it actually exposes `appendEntry`, but absence of that unrelated capability must not clear the freshly rebound factory writer. Shutdown and stale-writer detection continue to clear invalid writers, preserving durable ownership and fail-closed visibility.

## Regression test

`pi-extension/src/session/sdk_session_projection.test.ts` models the real ordering: bind a fresh factory writer at `session_start`, then bind a message-only `withSession` context. It asserts the writer remains available and the next session-scoped event appends durably. Before the fix it fails because `hasTranscriptPersistence()` becomes false.

## Implementation notes

- **Execution capability:** `openai-codex/gpt-5.6-sol` at high reasoning, selected by the caller for a live-only lifecycle regression spanning real Pi `SessionManager`, extension durability, relay, and app session gating.
- **Files changed:** `pi-extension/src/session/sdk_session_projection.ts` and `pi-extension/src/session/sdk_session_projection.test.ts`.
- **Fails-before unit evidence:** the focused test failed at `hasTranscriptPersistence()` with `Expected: true / Received: false` after the message-only replacement context rebound.
- **Trace:** before the fix, session `…0034cf77` appended `user_confirmed`, `assistant_committed`, and `assistant_done`; after `session_new` selected `…a2dbc2d1`, the real SDK accepted the next prompt and ran both user/assistant `message_end` hooks under `…a2dbc2d1`, but emitted zero `outpost-pi.transcript-event.v1` appends. Durable-first visibility therefore emitted no echo/reply and the app timed out. After the fix, replacement session `…7c863cbf` appended `assistant_committed`, `assistant_done`, and `user_confirmed` under that same session, and the app received the echo/reply. The late old-session `action_ok` remained correctly rejected by the app gate and was not causal.
- **Focused regression:** the new test passes after the one-line ownership correction.
- **Full extension verification:** `corepack pnpm typecheck`, `corepack pnpm test` (1,090 passed, 3 skipped), and `corepack pnpm build` all pass.
- **Original reproduction:** final uninstrumented `e2e/run-live.sh state-shapes` passes 3/3 plus debug-capture retrieval.
- **Requested soak:** `python3 e2e/live_soak.py --duration 300 --seed 20260901` exits 0. The scheduled real multi-session round trip completes; all 6 sends have echoes; 12 checkpoints report replay-dedup, transcript-projection, ordering, and identity invariants clean. Evidence: `.work/session-notes/live-soak-20260825T200849Z-20260901/report.md` (local-only).
- **App verification:** no app source or test changed; both live runs rebuilt and exercised the debug APK. Per request, standalone `flutter analyze` and the full app suite were not required for an untouched app surface.
- **Lane hygiene:** emulator `emulator-5554` is down, no live E2E containers or generated `.live_soak_*.dart` remain, and retained `.work/artifacts/app-0.8.0+16-debug.apk` remains present with SHA-256 `76ad2620e7e05466086ffee8a9cb122ba03af5ef8140444d97168b4d6a0202b9`.
- **Adjacent issues parked:** none; the observed late old-session action ACK is an expected scoped-control drop after authoritative room-metadata rotation.

## Review (2026-08-25)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: none
**Rejected**: none

**Notes**: Standalone-story bounded inline review, one pass; no independent, fresh-context, or cross-model reviewer ran. Correctness review confirmed that shutdown and stale-append paths still evict invalid writers, while only a message-only `withSession` rebind stops clearing the writer established by the current `session_start`. The change preserves durable-first visibility and session-scoped event identity, changes no wire/public contract, and introduces no auth, input, or resource-lifecycle surface. The failure-first unit guard, uninstrumented 3/3 state-shapes run, clean requested soak, full extension suite, diff hygiene, and lane cleanup provide complete acceptance evidence. Foundation/protocol assertions remain current; no durable documentation update is needed.
