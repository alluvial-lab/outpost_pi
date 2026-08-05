---
id: story-mobile-slash-command-passthrough-editor
kind: story
stage: drafting
tags: [pi-extension]
parent: feature-mobile-slash-command-invocation
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-04
updated: 2026-08-04
---

# Transparent passthrough editor (the editor-seam foundation)

Unit A of `feature-mobile-slash-command-invocation` — the riskiest, make-or-break
unit. The spike proved `editor.onSubmit("/new")` reaches pi's command parser; this
unit makes the editor a **transparent passthrough** so direct TUI typing is
unaffected, and re-captures the ref across session replacement.

## START by validating (the riskiest assumption)

`ctx.ui.setEditorComponent` REPLACES the editor. Before building, confirm the
default editor can be **obtained/wrapped** (the factory receives
`(tui, theme, keybindings)` — is the default editor constructable/delegatable so
the custom editor proxies rendering + keys to it?). If a transparent wrap is NOT
feasible (would require reimplementing the editor), STOP — record the finding +
escalate to the stdin-emit stopgap or the upstream API. Do not ship a broken wrap.

## Change

- `pi-extension/src/**` — install a custom editor via `ctx.ui.setEditorComponent`
  that delegates all rendering + key handling to the default editor (transparent
  proxy) and exposes an inject seam (`onSubmit(cmd)`).
- Re-capture the editor ref on session replacement (`new`/`fork`/`reload` → fresh
  editor; stale refs must not crash).

## Acceptance

- [ ] Direct TUI input unaffected (type `/reload` in a herdr pane → pi reloads).
- [ ] Programmatic `onSubmit("/new")` → new session; `onSubmit("/reload")` → reload;
      an extension command round-trips.
- [ ] Editor ref re-captured after session replacement (no stale-ref crash).
- [ ] Validation note records default-editor-wrap feasibility before implementation.

## Ordering

`depends_on: []` (foundation). Gates B, C, D.
