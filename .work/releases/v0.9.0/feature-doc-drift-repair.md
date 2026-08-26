---
id: feature-doc-drift-repair
kind: feature
stage: done
tags: [docs, prose]
parent: null
depends_on: []
release_binding: v0.9.0
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Documentation drift repair (v0.4.0 + v0.5.0 batches, one prose pass)

## Brief

Formed by groom 2026-08-26 from two stale-contract sweep batches — both
bounded repairs of durable documentation surfaces claiming things the code
no longer does. No code surface; one authoring pass.

Sources (bodies retained in `.work/archive/`):
- `backlog-v040-doc-drift-batch` (gate-cruft C5 + gate-docs D4-D8, 5 findings)
- `gate-docs-v050-doc-drift-batch` (7 findings, verified 2026-08-15)

## Findings (carried forward; re-verify line anchors at authoring time)

1. `pi-extension/src/composition_root.ts:112-116` — comment overclaims SIGKILL/SIGTERM skips session_shutdown; hot-reload path uses graceful SIGTERM and a session_shutdown hook is registered. Limit to ungraceful SIGKILL.
2. `pi-extension/README.md:136` — `/new` documented only as `ctx.newSession()`; omit the restart-managed EXIT_FRESH_SESSION path. Document both.
3. `.agents/skills/pi-extension-typescript/SKILL.md:99-107,169` — omits `agent_settled` hook; names EXIT_DAEMON_FRESH_SESSION vs actual EXIT_FRESH_SESSION (`rpc_child.ts:45`).
4. `pi-extension/src/index.ts:2168-2170` — router comment attributes all tool broadcasts to SDK handlers; `_deliverMeshMessageToAgent` also broadcasts. Clarify.
5. `AGENTS.md:311-313` — says arm is a no-op when disabled; `hot-reload.sh:69-72` exits 1. Clarify.
6. `CHANGELOG.md` — two `## [v0.5.0]` headings collide (tagged 2026-08-15 vs pre-rebrand 2026-06-29, around :87/:664 at groom time). Disambiguate the historical heading.
7. "Space Mono everywhere" overclaims vs Noto Sans Mono banner fallback (`scripts/generate-brand-assets.py:167-168`). Qualify or regenerate.
8. `README.md:16` "Official site — TBD" → point at the established site.
9. Dark-only assertions contradict dual-mode reality — `site/README.md:32`, `.agents/skills/next-site/SKILL.md:81`, cockpit `file_icon_map.g.dart:9` comment.
10. Six skill descriptions call the product "Remote Pi" — rename current-product prose to Outpost-Pi; keep Remote Pi for provenance/history.
11. `docs/DECISIONS.md:41-43` — "origin is the only configured remote" vs configured fetch-only provenance remote; state the durable policy (origin is the only push target).
12. `docs/release-uat.md:67-68` — retired locations; point at durable surfaces.

Finding 5 of the v0.5.0 batch (skill descriptions) appeared partially
resolved at groom re-check — re-verify before editing.

## Verification

Every edited surface re-checked against the code it describes (docs are
current-state contracts per `.agents/rules/documentation-discipline.md`);
link/reference sweep over the diff.

## Design decisions

- Re-verified every carried-forward anchor against the current tree before
  editing. Where source had moved, the current symbol/comment was used as the
  contract rather than preserving stale line numbers.
- Qualified the Space Mono claim instead of regenerating assets: the checked-in
  banner generator intentionally uses the approved Noto Sans Mono fallback on
  this VM, while the SVG source and product surfaces retain the Space Mono
  contract.
- Replaced current-product `Remote Pi` prose in the six named skill reference
  surfaces with `Outpost-Pi`; preserved `remote-pi-*` citation handles and
  `remote_pi` provenance/path identifiers.
- Repointed the UAT automation reference to the checked-in
  `e2e/run-pairing.sh` surface and the deploy reference to the actual
  `AGENTS.md#paired-wire-changes-deploy-together` heading.

## Implementation notes

- Execution capability: `openai-codex/gpt-5.6-luna` xhigh (caller-selected);
  direct-read, bounded multi-surface prose repair with code re-verification.
- Review weight: `standard` (source: caller note/default).
- Files changed:
  - `pi-extension/src/extension/composition_root.ts`
  - `pi-extension/README.md`
  - `pi-extension/src/index.ts`
  - `site/README.md`
  - `cockpit/lib/app/core/ui/file_icons/file_icon_map.g.dart`
  - `AGENTS.md`, `README.md`, `CHANGELOG.md`, `branding/README.md`
  - `docs/DECISIONS.md`, `docs/release-uat.md`
  - `.agents/skills/pi-extension-typescript/SKILL.md`
  - `.agents/skills/flutter-mobile/SKILL.md`
  - `.agents/skills/flutter-desktop-cockpit/SKILL.md`
  - `.agents/skills/rust-relay/SKILL.md`
  - `.agents/skills/next-site/SKILL.md`
  - `.agents/skills/code-design-principles/SKILL.md`
- Tests added/removed: none; this is a documentation-only repair. No build
  suites were run per the item brief.
- Simplification: removed duplicate/stale release and lifecycle wording;
  no compatibility or runtime behavior changed.
- Discrepancies from design: finding 5's old `AGENTS.md` no-op claim is absent
  from the current root file; it was verified already-resolved and not edited.
  The carried-forward skill-description finding was rechecked and remained
  stale across all six named skills, so it was edited rather than marked
  resolved.
- Adjacent issues parked: none.

## Finding disposition

- **Edited and re-verified:** 1, 2, 3, 4, 6, 7, 8, 9, 10, 11, and 12.
  Finding 7 updated `AGENTS.md`, `branding/README.md`, and `CHANGELOG.md`;
  finding 10 updated the six skill files listed above.
- **Already-resolved:** 5. The current `AGENTS.md` makes no no-op claim for
  `arm`; the current `scripts/hot-reload.sh` returns status 1 when the toggle
  is off, so no documentation edit was warranted.
- **Verified-fixed before authoring:** none.

## Verification evidence

- `git diff --check 32f9ed9a..HEAD` passed.
- Rechecked lifecycle paths: `registerLifecycleHooks` registers
  `session_shutdown`; `agent_settled` flushes mesh ingress and gates hot reload;
  `rpc_child.ts` exports `EXIT_FRESH_SESSION = 42`; restart-managed `session_new`
  exits with that code and relaunches without `--continue`.
- Rechecked dual-mode site/Cockpit state in `site/src/app/globals.css` and
  `cockpit/lib/app/core/ui/themes/app_theme.dart`.
- Rechecked repository remotes: `origin` is the push target and `upstream`
  is the configured provenance fetch remote.
- Rechecked changed local links: `../e2e/run-pairing.sh` and
  `../AGENTS.md#paired-wire-changes-deploy-together` resolve; all changed
  Markdown structure and references remain intact.

## Review (2026-08-26)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: none
**Rejected**: none

**Notes**: Standard feature review was performed as a fresh host-context
contract pass over the full item diff: each finding was rechecked against
current source, changed docs were proofread in context, stale naming/heading
patterns were searched, and local links were resolved. The delegated worker
surface did not expose an independent reviewer tool; no code/build suite was
needed for this prose-only item, and `git diff --check` passed.

## Phase-8 addition (2026-08-26)

`PROTOCOL.md`'s `session_new` contract was rolled forward after the completion
review finding: it now documents both the in-process `ctx.newSession()` path
and the managed restart-fresh fence/drain/dispose/exit/relaunch path, and names
successor room metadata with a new canonical `session_id` as the authoritative
convergence signal. The existing schema-owned `delivery_retry` entry was
verified against the schema and generated projections; no protocol-table
addition was needed.

