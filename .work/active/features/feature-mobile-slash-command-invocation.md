---
id: feature-mobile-slash-command-invocation
kind: feature
stage: implementing
tags: [app, pi-extension, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-04
updated: 2026-08-04
---

# Mobile slash-command invocation

## Brief

Let the mobile app issue **arbitrary pi slash commands** (`/new`, `/reload`,
custom skills, extension commands like `/outpost-pi …`) — not just `newSession`.
In-process via the **editor-seam** (`ctx.ui.setEditorComponent` + `editor.onSubmit`),
which the spike proved reaches pi's native command parser generally (supports
everything the TUI can type). Delivered through **two entry modes** (operator
decision): a dedicated **command picker/sheet** AND **`/`-routing in the composer**.
Unblocks the original `/new` bug (the `session_new` action retires in favor of
issuing `/new` natively).

## Origin

- `.work/backlog/backlog-mobile-new-button-newsession-no-command-ctx.md` — the
  `/new` bug + the confirmed root cause (mobile can't issue slash commands;
  `sendMessage` → `_wakeAgent` prompt-injects, bypassing pi's command parser)
  + the spike finding (editor-seam works in TUI mode; `pi.sendUserMessage("/x")`
  does NOT; no supported SDK submit-input API).
- The operator's criterion: a direction that also supports `/reload`, skills,
  and extension commands — which the editor-seam satisfies (general parser
  access) and restart-fresh does not (`/new` only).

## Design decisions (operator, 2026-08-04)

- **Both entry modes:** (1) a dedicated command picker/sheet; (2) `/`-routing in
  the existing composer.
- **Mechanism: in-process editor-seam (a).** Long-term clean = (c) an upstream
  host-operation/submit-input API in `@earendil-works/pi-coding-agent` (tracked,
  not blocking). (d) restart-fresh rejected (`/new` only). (b) `process.stdin.emit`
  remains a known stopgap, not the real answer.
- **`session_new` action retires:** it maps to issuing `/new` via the seam; the
  fragile `ctx.newSession()`/command-context path is removed.

## Implementation Units

### Unit A — Transparent passthrough editor (extension) — RISKIEST
**Story**: `story-mobile-slash-command-passthrough-editor`
**Depends on**: none (foundation).

Install a custom editor via `ctx.ui.setEditorComponent(...)` that (1) **faithfully
proxies the default editor** (rendering + key handling) so direct TUI typing in
herdr panes is unaffected, and (2) exposes an inject seam (`editor.onSubmit(cmd)`)
for programmatic command submission. Re-capture the editor ref across session
replacement (`new`/`fork`/`reload` → fresh editor; refs go stale).

**START by validating** the default editor can be obtained/wrapped (the SDK's
`setEditorComponent` factory receives `(tui, theme, keybindings)` — confirm the
default editor is constructable/delegatable). If a transparent wrap is NOT
feasible (would require reimplementing the editor), STOP and escalate to (b)
stdin-emit or (c) upstream — record the finding rather than ship a broken wrap.

**Acceptance:**
- [ ] Direct TUI input is unaffected (type `/reload` in a herdr pane → pi reloads).
- [ ] Programmatic `onSubmit("/new")` → pi starts a new session; `onSubmit("/reload")`
      → pi reloads; an extension command round-trips.
- [ ] Editor ref re-captured after session replacement (no stale-ref crash).
- [ ] A validation note records the default-editor-wrap feasibility (the riskiest
      assumption) before implementation proceeds.

### Unit B — Extension command-submission action + wire
**Story**: `story-mobile-slash-command-extension-action`
**Depends on**: [Unit A].

Expose a wire action (e.g. `slash_command { command }`, or extend the existing
`session_new` to drive `/new`) that calls `editor.onSubmit(cmd)`. Ack/error:
`onSubmit` returns `void` → confirm via lifecycle events (`session_start
reason=new` for `/new`, etc.); map ack/timeout to a structured `action_ok`/
`action_error`. Map `session_new` → `onSubmit("/new")` and retire the
`ctx.newSession()`/command-context path (the original bug). Wire schema for the
action (`protocol/schema/app-pi-client.schema.json` + dart fixture + regen).

**Acceptance:**
- [ ] App `slash_command("/reload")` → pi reloads; `session_new` → new session
      (via `/new`, not the old fragile path).
- [ ] Structured ack/error (success confirmed via lifecycle, not fire-and-forget).
- [ ] `check:protocol` clean; the old `newSession unavailable` throw is gone.

### Unit C — App composer `/`-routing
**Story**: `story-mobile-slash-command-composer-routing`
**Depends on**: [Unit B].

When the user types a `/`-prefixed string in the composer and sends, route it as
a **command** (the `slash_command` action) instead of `sendMessage` (which
prompt-injects). Detect the `/` prefix at send time; route accordingly. Bare `/`
or unknown commands still go to the parser (pi surfaces the error).

**Acceptance:**
- [ ] Typing `/reload` in the mobile composer → pi reloads (not sent to the agent
      as a prompt).
- [ ] Non-`/` input unchanged (still a normal prompt).

### Unit D — App command picker/sheet
**Story**: `story-mobile-slash-command-picker-sheet`
**Depends on**: [Unit B] (parallel with C).

A dedicated command-entry UI (browse/search + free-text) modeled on the existing
quick-actions sheet. **Phase 1:** free-text command entry + a small set of common
commands (`/new`, `/reload`, `/outpost-pi …`). **Phase 2 (follow-up):** full
command-catalog enumeration (querying the extension for all available commands —
native + extension-registered + skills), which needs a new command-catalog wire
surface.

**Acceptance:**
- [ ] Picker lets the user select/type a command → invokes the `slash_command`
      action; result surfaces in the transcript.
- [ ] Phase-1 common-command set + free-text entry works end-to-end.

## Implementation Order

1. **A** (passthrough editor) — riskiest; **validate the default-editor wrap first**,
   then implement. Gates everything.
2. **B** (extension action + wire) — `depends_on` A.
3. **C** and **D** (app both modes) — `depends_on` B; run in parallel.

## Risks (pre-mortem)

- **Riskiest assumption — transparent default-editor wrap.** `setEditorComponent`
  replaces the editor; a custom editor that doesn't perfectly proxy rendering +
  keys would degrade direct TUI typing. Unit A validates this before building;
  if infeasible, escalate to (b) stdin-emit or (c) upstream.
- **Editor-ref staleness** across session replacement — re-capture on `new`/`fork`/`reload`.
- **`onSubmit` returns void** — ack via lifecycle events (latency + error detection
  imprecision); design the ack contract carefully.
- **TUI-only** — the editor-seam no-ops in RPC/daemon mode; the daemon keeps its
  existing restart-fresh path for `/new` (unaffected).
- **Command catalog** for the picker is phase 2 (needs a wire surface to enumerate
  commands incl. skills).

## Testing

- **A:** harness test installing the passthrough editor → assert direct input
  proxies + `onSubmit` reaches the parser + re-capture after replacement.
- **B:** action dispatch → `onSubmit`; structured ack via lifecycle; the
  `session_new` → `/new` mapping.
- **C/D:** app tests for `/`-routing + picker invocation.
- **E2E:** `/new`, `/reload`, and a custom skill all round-trip from mobile; the
  original "New button" repro (post-restart/re-pair) now works.

## Out of scope

- The upstream SDK submit-input API (c) — tracked as the long-term clean
  replacement; not blocked on.
- Full command-catalog enumeration (picker phase 2).
- Daemon-mode `/new` (unchanged — it keeps restart-fresh).
