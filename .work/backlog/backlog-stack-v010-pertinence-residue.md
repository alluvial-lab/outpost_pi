---
id: backlog-stack-v010-pertinence-residue
created: 2026-08-28
updated: 2026-08-28
tags: [app, pi-extension, deps, workflow]
---

# v0.10.0 stack-program pertinence sweep — retest/watch/risk residue

Post-upgrade sweep (2026-08-28) of everything the v0.10.0 stack program
moved (Flutter 3.44.4→3.47.1 — no stable 3.45/3.46 exist, the stable line
jumped; pi SDK 0.80.6→0.84.3; app plugin refresh; relay crate refresh)
mapped against open bugs and field evidence. Full mapping produced by the
sweep worker (session 2026-08-28); this item carries the actionable
residue. No RETIRE-CANDIDATEs: nothing upstream replaces the local
WebSocket deadline, reconnect ladder, or doze-delivery work.

## WATCH

- **Flutter PR #191453** (fixes #191156 background-return stale insets +
  #190974) is **unmerged** — not merely missing from 3.47.1. Keep the
  stale-IME watchdog; when a stable release contains it, reproduce
  background-return / cover-display / fold-unfold / no-focused-field
  plateaus on the Pixel Fold before considering watchdog retirement.
- Note: the 3.47 "reset system UI visibility flags in edge-to-edge" fix
  was already in **3.44.2** — do not credit the upgrade with it or use it
  to retire any inset workaround.

## RETEST (device / manual — candidates for the release-UAT runbook)

- **Pixel Fold posture/rotation stress** during cold start, reconnect
  hydration, and active streaming: 3.47 ships Android Mali/AHB Impeller
  swapchain + destruction fixes (one fixes a Mali rotation crash at
  startup; Tensor-class GPUs are Mali-family). Watch for crash/black
  frame/frozen frame.
- **Gboard text input**: 3.47 fixes phantom Shift synthesis while Gboard
  holds META_SHIFT_ON — retest shift-lock, Backspace/Enter, tap/drag
  selection in chat input and selectable transcript text.
- **share_plus 13.3** moves Android share I/O off the main thread —
  share the largest permitted debug log while streaming/scrolling; no
  visible stall, byte-identical NDJSON.
- **pi 0.84 event-bus scoping** (listeners scoped to the registering
  runtime, stale listeners removed on reload/disposal — pi PRs #7656
  0.84.0, #8424 0.84.3): after a full process restart, repeated
  /reload cycles + one subagent create/complete/fail sequence — require
  exactly one background transition per event, no ghost/duplicate
  child-session authority (directly intersects the background-work
  tracker and runtime_coordinator subscriptions). Also exercise one
  failed extension init + recovery.
- **pi model catalogs** moved to interactive/RPC refresh with
  generation-guarded publication (0.81/0.84): after full Pi restart,
  model get/list/set from the phone with healthy + unavailable catalogs;
  cached models stay usable, stale refreshes never overwrite newer state.

## NEW-RISK

- **gpt_markdown 1.1.8→1.2.1**: bare-URL autolinking is now ON by
  default (partial/bare URLs become changing tap targets DURING
  streaming — interacts with the streaming-chat surfaces) and a new
  opt-in streaming renderer (`isStreaming`) we do not set (no free
  flicker win). Retest partial/bare URLs, malformed links, long inline
  code in long streaming replies. Do NOT enable its reveal animation
  without separate UX/perf evidence.

## Already handled

- deferred-migrations backlog groomed same day: pi SDK 0.84.3 and
  share_plus 13 were absorbed by the stack program (see
  backlog-deferred-dependency-migrations.md updated state).
