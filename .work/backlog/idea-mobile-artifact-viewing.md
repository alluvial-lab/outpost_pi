---
id: idea-mobile-artifact-viewing
created: 2026-08-25
updated: 2026-08-25
tags: [app, ux, idea]
---

# No way to read repo .mds/artifacts from mobile

Operator pain (2026-08-25): artifacts agents prepare (work items, reports,
groom reports, goldens, captures, changelogs) live in the repo; on mobile
the only access is (a) having the agent print the file into chat — context-
expensive and ugly for long docs — or (b) going to a workstation. Mobile is
the primary operator surface; it should be able to VIEW repo artifacts.

## Options to explore at scope time

- **Artifact delivery as a rendered message**: extend the debug-capture
  upload's reverse path — an extension-side command ("show me
  `.work/…/report.md`") that reads a bounded file and delivers it as a
  structured, markdown-rendered document message (not a raw chat dump);
  reuses the sealed owner channel + the existing markdown chat rendering.
- **Slash-command vehicle**: natural companion to
  `feature-mobile-slash-command-invocation` (drafting) — the command
  surface is where "show file" would live; coordinate the designs.
- Constraints to respect: path containment (same guard family as capture
  upload), size bounds, no secrets exfiltration surface (the channel is
  sealed to the owner, but bound file types/sizes), binary formats need a
  story (link-out vs. inline preview vs. refusal).
- Cockpit already reads files locally (desktop); this is the mobile parity
  gap.

Related: `idea-pair-code-clipboard-copy` (opposite-direction ergonomics),
`feature-mobile-slash-command-invocation`.
