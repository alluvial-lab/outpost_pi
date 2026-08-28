---
id: story-cleanup-ext-sdk084-compat-batch
kind: story
stage: done
tags: [pi-extension, cleanup]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-28
updated: 2026-08-28
---

# Remove pre-0.84 SDK compatibility surface from the extension (batch)

From the 2026-08-28 version-delta code sweep — read
`.work/backlog/backlog-post-stack-v010-code-cleanup.md` (candidates 1–5
with file:line, confidence, sizes) before starting. The extension rode
pi SDK 0.80.6→0.84.3 in v0.10.0; these five verified candidates are code
written against pre-0.84 behavior that the installed SDK makes dead,
redundant, or simpler. Verify each against the installed types under
`pi-extension/node_modules/@earendil-works/pi-coding-agent/dist/`.

## Work

1. **[HIGH]** Replace the hand-written SDK loader fake in
   `test/support/sdk_session_replacement_harness.ts` with the installed
   `loadExtensionFromFactory` (pattern already used by
   `runtime_coordinator.integration.test.ts`); delete
   `createExtensionShell()`/`createHarnessExtensionApi()`. Simplify the
   `Partial<ExtensionAPI>.events` guard in composition_root only if
   candidate 1 makes it trivially safe — do not force it.
2. **[HIGH]** Delete the fallback model runtime/registry: all of
   `src/actions/registry.ts`, handlers.ts:94-120,267-314 fallback paths,
   index.ts:3404-3425 call sites. Production model actions require the
   live action context (`ctx.modelRegistry` is unconditional).
3. **[MEDIUM — verification edge]** Drop the duplicate synchronous
   `refresh()` in `model_set`/`list_models` (handlers.ts:278-282,311-313).
   VERIFY JSON/daemon mode first: pi's background catalog refresh runs in
   interactive/RPC modes only — if daemon-mode model listing would go
   stale without the explicit refresh, KEEP a minimal explicit refresh on
   that path only and note it; do not force the removal.
4. **[HIGH]** Collapse model hydration onto public `ctx.model`: delete
   first-turn late hydration (index.ts:1632-1644), private `getModel`
   adapters (index.ts:2102-2118, handlers.ts:74-100,314,
   sdk_session_projection.ts:1080-1120), the configured-default
   prediction path, and stale fake expectations
   (extension.test.ts:6927-6995). `model_select` events still carry
   later changes.
5. **[MEDIUM — verification edge]** Drop manual unsubscribe retention in
   `background_activity.ts` (0.84 auto-unregisters a runtime's
   listeners). VERIFY an event arriving during the awaited
   session_shutdown teardown window stays safe; if not provable, keep
   the retention and note why.

## Acceptance evidence

- Net line removal roughly as estimated; no behavioral regressions.
- Full `corepack pnpm typecheck && corepack pnpm test && corepack pnpm
  build` green from pi-extension/ (test count may shrink where stale
  fake expectations are deleted — that is intentional; name the removed
  tests in implementation notes).
- Verification edges 3 and 5 explicitly resolved with evidence (removed
  with proof, or retained with a one-line reason each).

## Implementation notes

- **Candidate 1 — removed.** `SdkSessionReplacementHarness` now loads the
  production factory through the installed SDK `loadExtensionFromFactory`; the
  handwritten `createExtensionShell()` and `createHarnessExtensionApi()` fake
  were deleted. The composition root's `Partial<ExtensionAPI>.events` guard
  was intentionally retained: legacy ping fixtures still pass a non-object
  placeholder, so candidate 1 did not make that seam trivially safe. The
  replacement suite still passed against the real runtime staleness guards.
- **Candidate 2 — removed.** Deleted `src/actions/registry.ts` and all fallback
  registry/provider plumbing. `model_set` and `list_models` require the live
  session `ctx.modelRegistry`; the route returns a session-unavailable error
  rather than constructing a separate registry.
- **Candidate 3 — retained only where needed.** The unconditional refresh was
  removed from the interactive path, but a minimal `refresh()` remains for
  `ctx.mode === "rpc"`/`"json"` (and the daemon marker). Installed SDK evidence
  shows `InteractiveMode` schedules its background catalog refresh, while the
  long-lived RPC/JSON paths do not; the service startup refresh is only an
  initial snapshot. This avoids stale daemon/JSON catalogs. Tests assert zero
  refreshes in TUI mode and one refresh in RPC mode.
- **Candidate 4 — removed.** Model hydration now uses public `ctx.model` at
  relay startup and in `models_list`; first-turn late hydration, private
  `getModel` adapters, and configured-default prediction were deleted.
  `model_select` remains the later-change source. Removed/replaced stale test
  names: `hello carries \`model\` from getModel() when ctx.model is absent
  (daemon path)`, `hello carries \`model\` from configured default settings
  (idle daemon path)`, `prefers ctx.modelRegistry over the fallback registry`,
  `registry refresh failure surfaces as error envelope`, and the old
  `ctx.getModel` wording for `omits \`current\``; the latter two were replaced
  by live-registry/current-`ctx.model` assertions rather than weakening tests.
- **Candidate 5 — removed.** Deleted manual unsubscribe-closure retention;
  `pi.events.on` is now owned by the installed SDK runtime, while tracker
  disposal still clears state and marks callbacks inert. The new
  `SDK-owned listeners remain safe during awaited shutdown and auto-unregister
  afterward` test emits during the pending shutdown handler, then invalidates
  the runtime and verifies a late terminal event is ignored.
- **Net source/test delta:** 220 additions and 392 deletions, for **172 fewer
  lines** (including the explicit SDK listener-lifecycle evidence test).
- **Verification:** targeted extension, action, projection, composition,
  background-activity, runtime-coordinator, and replacement-harness suites
  passed: 7 files / 345 tests. The required commands also passed from
  `pi-extension/`: `corepack pnpm typecheck`, `corepack pnpm test` (63 files,
  1,119 passed, 3 skipped), and `corepack pnpm build`.
