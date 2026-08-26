---
id: feature-doc-drift-repair
kind: feature
stage: drafting
tags: [docs, prose]
parent: null
depends_on: []
release_binding: null
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
