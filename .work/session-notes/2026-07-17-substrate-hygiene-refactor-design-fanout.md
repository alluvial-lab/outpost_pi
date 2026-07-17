# Session note — 2026-07-17 (substrate hygiene + board status + refactor-design fan-out)

## Goal

Operator asked "what's the status of the board?" and the answer snowballed into
a full substrate-hygiene + design campaign: correct a misread of the shipped
release version, then run a groom, rebind post-hardfork done work to v0.1.0,
delete pre-rebrand tags, fix durable version refs, fan out refactor-design
across 6 `[refactor]` features, and run the one misrouted feature through
feature-design. The session ended with 6 designed features at `stage:
implementing`, ready for `implement-orchestrator` in a fresh context.

## What shipped this session (22 commits, `origin/main..HEAD`)

### 1. Substrate correction — v0.1.0 is the live release (not v0.6.0)

The first board-status read conflated the pre-rebrand v0.6.0 generation with
the current state. The operator corrected it. **v0.1.0** is the Outpost-Pi
rebrand release (shipped 2026-07-12, git tag `v0.1.0`); all subprojects at
`0.1.0` on disk. The v0.6.0 / component-v1.x releases are the prior
remote_pi generation.

### 2. Tags + durable refs + rebind (`c271428`, `5b06250`)

- Deleted 23 pre-rebrand git tags (local-only; origin has none). Only `v0.1.0`
  remains.
- `.work/CONVENTIONS.md` version-prefix table reset to 0.1.0 for all components.
- `epic-rebrand-to-outpost-pi.md` prose rewritten to not cite deleted tags.
- Rebound 73 done items (completed after the 07-12 cut) from `active/` into
  `.work/releases/v0.1.0/` with `release_binding: v0.1.0`. Release summary now
  shows 136 items bound (55 original + 73 rebound + 8 archived stubs).
- Untracked `.work/bin/work-view` (plugin-managed build artifact; was a 14.7 KB
  bash fallback, replaced by the real 772 KB Rust binary the agile-workflow
  plugin installs). Gitignored `.work/bin/`.

### 3. Groom — 12 disposed, 14 clusters identified (`a9e33ec`)

- 9 SUPERSEDED (premise addressed by shipped work) + 3 DUPLICATE folds → archived.
- 14 mergeable clusters surfaced (report inline; no scratch dir). Operator
  approved promoting all 14 + folding 4 overlap clusters into
  `epic-remote-session-resilience-refactor`.

### 4. Scope — 14 clusters → 14 features + 68 child stories (`20b2eda`)

- 10 standalone features + 4 children of the resilience epic.
- Backlog: 106 → 26. Active: 3 epics, 19 features, 80 stories.

### 5. Docs repair (`fa88cc2` + `dbcd577`)

`feature-repair-current-state-docs` `[prose]` — 6 drift fixes (composition-root
session hooks, peer-join broadcast location, cockpit README, relay CLAUDE.md
logging, DECISIONS.md 1 MiB→4 MiB limit, protocol.dart facade comment).
Fresh-context review caught 3 real errors (wrong type name `RemotePiRuntimePorts`
→ `OutpostPiRuntimePorts`, invented cockpit "owner identity" surface + missing
dev-VM build specifics, historical/imprecise DECISIONS prose). All fixed.

### 6. Rebrand epic rolled to done (`38a5651`, `9bf6224`, `dc29ed7`)

3 blocking children resolved:
- `story-refresh-current-protocol-security-docs` — PROTOCOL.md pairing/trust-model
  rewritten; the `pair_request`-signed-by-Owner claim was wrong (schema has no
  signature field, `additionalProperties: false`; authority is the authenticated
  relay transport `outpost-pi-relay-auth-v1`, not an inner signature).
- `story-wire-protocol-codegen-tests-into-check` — wired codegen unit tests into
  `protocol check` (5 tests, all 3 acceptance criteria verified green).
- `story-document-deferred-relay-volume-cutover` — **archived as superseded**;
  the cutover already shipped in `d04b7e7` (AGENTS.md `remote-pi-data`→
  `outpost-pi-data`, live container inspected). Story premise was stale on
  arrival.

### 7. Refactor-design fan-out — 6 features designed

6 read-only design agents (gpt-5.6-sol, high thinking), each producing a
Phase-7 refactor plan written into the feature body. All verified current-state
line numbers (gate findings were 2026-07-01; code drifted).

| Feature | Verdict | Commit |
|---|---|---|
| `feature-retire-legacy-piext-composition-seams` | ✅ 4 pure refactors | `9a19b70` |
| `feature-app-async-lifecycle-ownership` | ⚠️ misrouted as `[refactor]` → feature-design | `e94cfc9` |
| `feature-cockpit-async-action-ownership` | ✅ 7 of 8 pure refactors (ownAsync/Zone); 1 retagged | `ec8e6ce` |
| `feature-piext-lifecycle-delivery-promise-policy` | ✅ 3 pure refactors (explicit rejection observers) | `03213ee` |
| `feature-cockpit-typed-rpc-boundaries` | ✅ 2 pure refactors (RpcJsonObject + sealed RpcUiResponse) | `9de50b8` |
| `feature-finish-generated-protocol-adoption` | ✅ 5 pure refactors + 1 retag (`room_meta_updated` has no generated counterpart) | `38decfa` |

### 8. Feature-design on the misroute (`235847a`)

`feature-app-async-lifecycle-ownership` retagged `[refactor]`→`[app, lifecycle]`
and run through feature-design. 4 behavior-changing child stories spawned with
`depends_on` chain: startup-ownership → connection-persistence →
sync-failure-semantics; connection-persistence → mesh-publication. Design
decisions resolved (router awaits boot, ChatViewModel.initialize() awaited/
retryable/generation-guarded, per-peer latest-wins persistence, sync separates
awaited vs detached + terminal idle convergence, mesh typed mutation intent).

### 9. Frontmatter fixes (`81d471f`)

Feature-design's `work-view --blocking` cycle-check caught 3 parse errors from
earlier session edits: unquoted `:` in volume-cutover `superseded_by`; duplicate
`updated` field in 2 released stories (rebind sed hit pre-existing `updated`
lines). Fixed all 3; full `.work` scan confirms zero remaining duplicates;
work-view runs clean.

## Current state — ready for implement-orchestrator

**6 features at `stage: implementing`** with full designs in their bodies:

| Feature | Kind | Child stories | Notes |
|---|---|---|---|
| `feature-retire-legacy-piext-composition-seams` | `[refactor,cleanup]` | 4 | pi-extension; 4 sequenced steps |
| `feature-cockpit-async-action-ownership` | `[refactor,lifecycle]` | 7 | cockpit; ownAsync/ownedAsyncAction boundary; 1 retagged out |
| `feature-piext-lifecycle-delivery-promise-policy` | `[refactor,lifecycle]` | 3 | pi-extension; explicit rejection observers |
| `feature-finish-generated-protocol-adoption` | `[refactor,protocol]` | 5 | cross-stack; generated DTO adoption; 1 retagged out |
| `feature-cockpit-typed-rpc-boundaries` | `[refactor,protocol]` | 2 | cockpit; RpcJsonObject + sealed RpcUiResponse |
| `feature-app-async-lifecycle-ownership` | `[app,lifecycle]` | 4 + 11 gate-* | behavior-changing; feature-design done |

Each feature body has: Refactor/Architectural Overview, per-step Current/Target
state with exact file:line + signatures, Implementation Notes, Acceptance
Criteria, Rollback, Implementation Order. Child stories are verification
checkpoints with `depends_on` chains.

**Retagged (behavior-changing) stories routing to feature/bug design:**
- `gate-cruft-empty-catch-formatter-reload` — `[cockpit, bug]`, parent: null
  (file_viewer.dart swallows _reloadFromDisk exceptions; logging/reporting
  changes the silent-fallback contract)

**Other active (not touched this session):**
- 13 features at `stage: drafting` (security hardening ×4, tests, e2e suite,
  reconnect repro, mobile parity ×2, outbound buffer, fork-vendor, contract
  gap audit, docs repair done)
- 2 epics at `stage: drafting` (`epic-remote-session-resilience-refactor`,
  `epic-targeting-and-session-lifecycle-contracts`)

## Next: implement-orchestrator

Run `/agile-workflow:implement-orchestrator` on the 6 implementing features.
They're independent (no cross-feature `depends_on`), so a fan-out is safe.
Each is one feature-owning worker baseline carrying its child stories as
verification checkpoints. Verification per subproject:
- pi-extension: `corepack pnpm typecheck` + `test` + `build` (needs
  `COREPACK_HOME=<writable>` + `--store-dir <writable>`; `/tmp` is read-only
  on this VM, so is `/home/agent/.local-state` — use e.g.
  `COREPACK_HOME=/home/agent/.corepack corepack pnpm --store-dir /home/agent/.pnpm-store`)
- relay: `cargo fmt --check` + `cargo clippy -- -D warnings` + `cargo test`
- cockpit: `flutter analyze` + `flutter test` (Flutter at
  `~/projects/outpost_pi/.tools/flutter`, `PUB_CACHE` must be set, `pub get --offline`)
- app: `flutter analyze` + `flutter test` (same Flutter path/PUB_CACHE)

## Key lessons / gotchas

- **The rebind's untracked-file trap.** Moving 73 done items on disk but not
  `git add`ing them meant a later `git add .work/active/stories/` swept their
  old tracked paths in as deletions. Caught in verification; fixed by staging
  the additions. Lesson: commit a substrate move before running unrelated
  substrate commands over the same paths.
- **`grep -c` returning 0 aborts `&&` chains.** Use `;` separators or
  `|| true` when grepping for absence.
- **`sed -i` on frontmatter can hit pre-existing fields.** The rebind's
  `updated:` date-rewrite produced duplicate `updated` lines where a file
  already had one mid-frontmatter. Always re-scan after a bulk frontmatter
  sed.
- **`/tmp` and `/home/agent/.local-state` are read-only** on this VM — affects
  corepack/pnpm and any tool expecting a writable temp.

## Live pairing verified

End of session: live pairing (mesh `outpost_pi`, relay connected, Android
device paired via QR). Confirms the v0.1.0 wire-paired cutover (auth
domain-separation, `to_room`, control-RPC discriminator) works end-to-end
with a real device post-rebrand.

## Git

22 commits ahead of `origin/main`, unpushed, working tree clean. All
commits are substrate-state + design; no production code changed except
the 6 docs-repair edits (PROTOCOL.md, protocol/README.md, schema,
cockpit/README.md, relay/CLAUDE.md, DECISIONS.md) and the codegen-test
wiring (`protocol/package.json` + `protocol/README.md`).
