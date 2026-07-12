---
id: epic-rebrand-to-outpost-pi-provenance
kind: feature
stage: done
tags: [rebrand, docs, legal]
parent: epic-rebrand-to-outpost-pi
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-11
updated: 2026-07-12
---

# Provenance: LICENSE, NOTICE, and authorship credit

## Brief

Establish the rebrand's legal and ethical provenance surface. Outpost-Pi is
built on Jacob Moura's `remote_pi` (MIT); the rebrand credits its origin
rather than scrubbing it. This feature owns three artifacts:

1. **Root LICENSE** — extend MIT to the whole repo. Today only
   `pi-extension/LICENSE` exists (`Copyright (c) 2026 Jacob Moura`). Add a
   root LICENSE covering all subprojects (app, relay, cockpit, site, rp-s3
   currently have no license file — default all-rights-reserved, a latent
   issue this resolves). Keep `Copyright (c) 2026 Jacob Moura` and add the
   operator's own copyright line for changes alongside, not replacing, the
   original.
2. **Root NOTICE** — new file crediting `remote_pi` / Jacob Moura as the
   foundation the fork was built on, and noting the Outpost-Pi rebrand.
3. **README credit** — root README acknowledges the upstream origin.

This is the legal floor (keep the MIT copyright + permission text) plus the
ethical bar (credit the original author/project wherever it makes sense:
LICENSE, NOTICE, README). Do NOT scrub the upstream author from the
provenance record.

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi`
- Position in epic: **independent legal/ethical slice.** No code behavior
  changes; touches only LICENSE, NOTICE, and README authorship prose. Can
  proceed in parallel with the mechanical rename and the wire-stable
  migration.

## What this feature does NOT cover (owned by sibling features)
- The ~68 files referencing `jacobaraujo7`/`jacobmoura` as **identifiers**
  (GitHub URLs, homepage `remote-pi.jacobmoura.work`, package homepage
  field) are rebranded by the mechanical-rename feature — they are
  identifiers, not the copyright notice, and are freely rebrandable. Only
  the **LICENSE copyright line** and **NOTICE/README credit content** are
  this feature's scope.
- External-surface provenance (GitHub repo rename, npm publish target) is
  deferred to the follow-up epic per the locked strategic decision.

## Foundation references
- `docs/VISION.md` — "Fork posture & provenance" (rebrand credits its origin)
- Parent epic `## Licensing picture` — the full MIT/provenance analysis
- Parent epic `## Strategic decisions` — provenance preserved, external
  surfaces deferred.

## Design notes (for `/agile-workflow:feature-design` or `/agile-workflow:prose-author`)

- This is a no-code-surface deliverable (docs/LICENSE/NOTICE prose). It
  routes through `prose-author` rather than `feature-design` — the design
  and implementation collapse into one inline authoring act.
- Verify the operator's preferred copyright line attribution before
  writing the LICENSE (the epic uses "the operator" as a placeholder; the
  design pass should confirm the name/form to use).
- The existing `pi-extension/LICENSE` is preserved as-is (it already
  carries the correct MIT + Jacob Moura copyright); the new root LICENSE
  extends the same license to the rest of the repo rather than replacing it.

## Implementation notes

- Added root `LICENSE` with the exact existing MIT permission text, retaining
  `Copyright (c) 2026 Jacob Moura` and adding `Copyright (c) 2026 Kevoun`, the
  operator name found in the repository's git author history.
- Added root `NOTICE` crediting `remote_pi` and Jacob Moura as the foundation,
  and noting the Outpost-Pi rebrand with MIT provenance preserved.
- The root README should add an "Acknowledgements" or "Based on" section
  crediting `remote_pi` / Jacob Moura. README editing remains owned by the
  sibling README story and was intentionally not performed here.
- Preserved `pi-extension/LICENSE` unchanged.

## Review (2026-07-12)

**Verdict**: Approve with comments

**Blockers**: none
**Important**: README acknowledgements section missing — filed as
`rebrand-readme-acknowledgements-section` (backlog). The epic's ethical bar
included README credit; LICENSE + NOTICE satisfy the legal floor and the
NOTICE credits the origin, but the README "Based on" section was deferred to
the mechanical-rename story which didn't add it. Small one-line fix.
**Nits**: none

**Notes**: Deep-lane review (feature scope). LICENSE content verified: standard
MIT, both copyright lines correct (Jacob Moura + Kevoun from git author
history). NOTICE concise and credits origin. pi-extension/LICENSE confirmed
unchanged. The README gap is the only above-nit finding; it's tracked, not
blocking.
