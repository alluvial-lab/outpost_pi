# Run notes — implement-orchestrator 2026-07-17

## Scope

6 features at `stage: implementing`, designed last session (refactor-design +
1 feature-design). All `depends_on: []` at item level. Resolved via write-set
analysis into 2 waves.

## Topology

### Conflict graph (write sets, not item depends_on)

- F1 (piext-composition) ↔ F2 (piext-delivery): `index.ts`, `ports.ts`,
  `composition_root.ts`, `legacy_ports.ts` (F1 deletes it; F2 step 2 references
  it pre-deletion). SERIALIZE.
- F1 ↔ F3 (generated-protocol): `relay_transport.ts` (F1 step 4 big rewrite of
  owner-channel; F3 step 2 small room_meta typing). SERIALIZE.
- F4 (cockpit-async) ↔ F5 (cockpit-rpc): `agent_session.dart`,
  `agent_transcript.dart` (different methods, same file). SERIALIZE.
- F2 ↔ F3: DISJOINT (F2 = sdk_session_projection + ports/root; F3 =
  relay_client + relay_transport + session_scope + codegen + relay). PARALLEL OK.
- F6 (app): fully independent.

### Waves

**Wave 1 (3 parallel workers — disjoint subprojects):**
| Worker | Feature | Model | Effort | Rationale |
|---|---|---|---|---|
| W1 | F1 retire-legacy-piext-composition-seams | sol | high | risky owner-channel bridge (step 4 "High risk, atomic"); sensitive reconnect/listener behavior |
| W2 | F5 cockpit-typed-rpc-boundaries | luna | high | 2 well-specified steps; normal delivery |
| W3 | F6 app-async-lifecycle-ownership | sol | xhigh | largest; behavior-changing; 6 units; generation guards + convergence semantics |

**Wave 2 (3 parallel workers — starts after Wave 1 commits):**
| Worker | Feature | Model | Effort | Rationale |
|---|---|---|---|---|
| W4 | F2 piext-lifecycle-delivery-promise-policy | luna | high | 3 well-specified steps; port-contract change but designed |
| W5 | F3 finish-generated-protocol-adoption | sol | high | cross-stack; codegen; generated contracts; 5 steps |
| W6 | F4 cockpit-async-action-ownership | sol | high | pane close() lifecycle contract; 7 stories; teardown races |

Wave-2 features depend on Wave-1 siblings by WRITE SET (clean-tree requirement),
not item depends_on. Reviews of Wave-1 features run concurrently with Wave 2.

## Effective review_weight

`standard` (default — no caller override, no project convention). One
independent review pass per feature, then adjudicate/fix/verify/close.

## Environment discoveries (pass to every worker)

### pi-extension (F1, F2, F3)
- **Do NOT use `corepack pnpm <cmd>`** — the deps-status RO-cache check tries to
  reinstall to a read-only COREPACK_HOME and fails. `node_modules` already
  populated; invoke tooling directly:
  - typecheck: `./node_modules/.bin/tsc --noEmit`
  - test (focused): `./node_modules/.bin/vitest run <path>...` (avoid bare
    `src/extension.test.ts` full run — see flake below)
  - test (full): `./node_modules/.bin/vitest run` (accept the 1 known flake)
  - build: `./node_modules/.bin/tsc` (emits `dist/`; uncommitted)
- **Known flake** `env-ext-test-cwd-lock-ordering-flake`: the "a second same-name
  agent joins" test in `extension.test.ts` fails because `~/.pi/remote/locks/`
  is **read-only** on this VM and stale `.sock` files accumulate. It is a
  pre-existing test-isolation issue, NOT a product bug. Document it honestly if
  it appears; do not weaken the test. Run targeted vitest (`-t "<name>"`) to
  avoid the full-suite ordering that triggers it.
- Codegen (F3): TS gen from `pi-extension/`: `node --import tsx
  ../tools/protocol-codegen/src/index.ts --target ts --out
  src/protocol/generated/protocol.generated.ts`. Rust check from `protocol/`:
  `node --import tsx scripts/list-types.ts | node
  ../tools/protocol-codegen/bin/protocol-codegen.mjs --target rust --schema -
  --out-dir ../relay/src/protocol/generated --check`.

### relay (F3)
- `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test`,
  `cargo build` — all work from `relay/`.

### cockpit (F4, F5)
- Flutter at `~/projects/outpost_pi/.tools/flutter`. Set
  `PUB_CACHE=/home/agent/projects/outpost_pi/.pub-cache` (writable).
- `flutter analyze` + `flutter test` from `cockpit/`. `.dart_tool` populated.

### app (F6)
- Flutter at `~/projects/outpost_pi/.tools/flutter`. Set
  `PUB_CACHE=/home/agent/projects/outpost_pi/.pub-cache`.
- **`flutter analyze` shows 228 pre-existing errors in
  `packages/outpost_pi_identity/test/owner_identity_test.dart`** (missing
  `test`/`expect` imports — a sub-package dev-dependency issue, NOT the app).
  App's own `lib`+`test` analyze clean. Run `flutter analyze lib test` to scope.
- `flutter test` from `app/`. `.dart_tool` populated.
- `flutter build apk --debug` is memory-sensitive on this VM (11G shared);
  may skip with a documented reason if it OOMs.

## Baseline verification (pre-dispatch)

- pi-extension `tsc --noEmit`: ✅ green
- pi-extension vitest (focused): ✅ green except the 1 known cwd-lock flake
- relay `cargo check`: ✅ green
- app `flutter analyze lib test`: ✅ clean
- cockpit: worker verifies its own baseline
- protocol codegen `--check`: ✅ matches committed output

## Worker contract (all workers)

- Own ONLY the feature + its child-story checkpoints. Child stories advance
  `drafting → done` as each step verifies (design lives in the feature body).
  Feature advances `implementing → review` after all children done +
  integrated verification green.
- One commit per item (`implement: <item-id>`), no push, no batched transitions.
- No nested delegation, no peeragent. Report blockers; don't expand scope
  silently. Preserve unrelated concurrent changes (other agents edit disjoint
  files).
- Land-mode detection: if the implementation already exists, reconcile the
  item body to as-built reality rather than forcing a flawed design.
- Design-flaw escape hatch: record `## Implementation discovery`, move the
  affected item back to `drafting`, return.
- Test integrity: repair stale fixtures/mocks; park real product bugs; never
  weaken/delete/skip a test to obtain green.
