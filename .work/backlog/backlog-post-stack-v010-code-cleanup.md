---
id: backlog-post-stack-v010-code-cleanup
created: 2026-08-28
updated: 2026-08-28
tags: [pi-extension, app, cleanup, deps]
---

# Post-stack-currency code cleanup — version-delta sweep candidates (2026-08-28)

**STATUS 2026-08-28 (same day): candidates 1–6 LANDED** via
`story-cleanup-ext-sdk084-compat-batch` (55e5d6f89; 4/5 removed, candidate 3
partially retained — explicit refresh kept on RPC/JSON/daemon paths on
freshness evidence; teardown-window listener test added for candidate 5;
net −169 lines, suite green) and `story-cleanup-app-flutter347-deprecations`
(e1bc2b340). **Only candidate 7 remains live** (Future.pause — floor-bound,
ride with the next pubspec `sdk:` floor change). The candidate details below
are retained as the sweep record.

Code-anchored counterpart to `backlog-stack-v010-pertinence-residue.md`:
cross-referenced the v0.10.0 version deltas (pi SDK 0.80.6→0.84.3,
Flutter 3.44.4→3.47.1, plugin bumps) against the CODE (not the board) for
simplifications/shrinkages. All candidates verified by read-only scanners
against the installed SDK types/sources. Honest-negative classes with no
candidates (deprecated-era API greps, gpt_markdown autolink handling,
share_plus/package_info call sites, abort-before-replacement +
getScopedModels + session_compact_failed harness methods,
runtime_coordinator subscribedBuses dedup guard, message_update payload)
were evaluated and cleared — do not rescan without new deltas.

## pi-extension (pi SDK 0.84.3)

1. **[HIGH, ~90–115 lines] Replace hand-written SDK loader fake** —
   `test/support/sdk_session_replacement_harness.ts:356-365,523-642`
   reimplements `ExtensionAPI` exposing `events` directly (0.80.6-era);
   the installed loader (`loadExtensionFromFactory`, dist/core/extensions/
   loader.d.ts) already wraps runtime-scoped subscriptions + failed-factory
   rollback. Use it as `runtime_coordinator.integration.test.ts` already
   does; delete `createExtensionShell()`/`createHarnessExtensionApi()`.
   Makes the `Partial<ExtensionAPI>.events` guard in composition_root
   easier to drop too.
2. **[HIGH, ~45–65 prod lines] Delete the fallback ModelRuntime/registry**
   — `src/actions/registry.ts` (whole file) + handlers.ts:94-120,267-314 +
   index.ts:3404-3425. `ctx.modelRegistry` was already unconditional in
   0.80.6; production model actions only run post-`session_start`. Dead
   local compatibility, not a new-API adoption.
3. **[MEDIUM, ~8–15 lines] Drop duplicate synchronous catalog refreshes**
   — handlers.ts:278-282,311-313 (`model_set`/`list_models` both
   `await refresh()`); since 0.81 the runtime refreshes catalogs itself
   and 0.84 publishes generation-guarded. VERIFY: desired behavior in
   JSON/daemon mode where no background refresh runs.
4. **[HIGH, ~25–40 prod + 25–40 test lines] Collapse model hydration onto
   public `ctx.model`** — delete first-turn late hydration
   (index.ts:1632-1644), private `getModel` adapters (index.ts:2102-2118,
   handlers.ts:74-100,314, sdk_session_projection.ts:1080-1120) and the
   configured-default prediction path + stale fake expectations
   (extension.test.ts:6927-6995). Current SDK resolves the session model
   before `session_start` and emits `model_select` on changes; `getModel`
   was never public.
5. **[MEDIUM, ~6–10 lines] Drop manual unsubscribe retention in
   `background_activity.ts`** — 0.84 auto-unregisters a runtime's
   listeners on invalidation. VERIFY: event arriving during the awaited
   session_shutdown teardown window.

## app (Flutter 3.47.1)

6. **[HIGH, tiny] `SizeTransition.axisAlignment` → `alignment`** —
   input_bar.dart:824-830; the deprecated arg + ignore + stale comment
   exist only because the old pin lacked `alignment`
   (transitions.dart:498-509 documents the migration).
7. **[MEDIUM, one line, FLOOR-BOUND] `Future.delayed(Duration.zero)` →
   `Future.pause()`** — chat_page.dart:519 (Dart 3.13 addition).
   Requires raising pubspec `sdk: ^3.11.5` — not worth a floor bump
   alone; ride it with the next floor-touching change.

## Landing shape

One cleanup feature with two child stories (extension batch: candidates
1–5, naturally one worker — 2+4 overlap in model handling; app micro:
6, optionally 7). All are behavior-preserving removals except 3/5's
verification edges — those get named in the story acceptance.
