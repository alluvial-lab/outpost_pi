---
id: idea-cockpit-viewmodel-split
created: 2026-07-23
updated: 2026-07-23
tags: [cockpit, refactor]
---

# Split cockpit_viewmodel.dart convergence file

`cockpit/lib/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart` is 1601 LOC
(advisor review 2026-07-23) — the next convergence-file candidate now that
`pi-extension/src/index.ts` has been halved. Candidate seams: terminal/PTY
state, session/agent state, file-tree state. Split along lifecycle-ownership
lines per `.agents/rules/code-design.md`.
