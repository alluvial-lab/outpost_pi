---
id: gate-docs-agent-reference-refresh-post-v050
kind: story
stage: implementing
tags: [docs, workflow]
parent: null
depends_on: []
release_binding: null
gate_origin: docs
created: 2026-08-15
updated: 2026-08-15
---

# Refresh the agent reference surface after the v0.5.0 dependency refresh

Post-hoc v0.5.0 docs-gate finding (merged with two cruft-gate duplicates).
Severity: **High** — stale agent references actively mislead every agent that
loads them; one instructs a nonexistent workflow.

## Severity
High

## Finding A — materially stale version guidance (docs High + cruft dup)

`.agents/skills/flutter-mobile/SKILL.md:10,168` pins guidance to
`go_router ^14.0.0` and **warns that 17.x is newer than the local pin** —
now inverted: the app pins `go_router ^17.5.0` (`app/pubspec.yaml:41`).
Same class: `.agents/skills/pi-extension-typescript/SKILL.md:10` +
`pi-extension/CLAUDE.md:20` (TypeScript 6.x → now 7.0.2,
`pi-extension/package.json:76`); `.agents/skills/rust-relay/SKILL.md:11`
(rusqlite 0.32.x → 0.40, `relay/Cargo.toml:23`);
`.agents/skills/next-site/SKILL.md:11` (Next 16.2.11 / React 19.2.6 →
16.3.x, `site/package.json:13-15`).

## Finding B — nonexistent workflow instruction (docs High)

`.agents/skills/next-site/SKILL.md:34` instructs: "then `./push-docker.sh`
after Docker Hub login" — no such script/workflow;
`site/CLAUDE.md:43-60` documents the actual local `./build-docker.sh`
no-registry/no-login posture. An agent following the skill would hunt for a
script that doesn't exist (or worse, improvise a registry push).

## Remediation direction
One sweep across the six `.agents/skills/*/SKILL.md` + `pi-extension/CLAUDE.md`:
refresh version headers and dependency pins from current manifests, fix the
inverted go_router warning, replace the push-docker instruction with the
build-docker workflow. Keep source-handle citations (`[remote-pi-...]{1}`)
pointing at the manifests so drift is self-evident next time.
