---
id: epic-rebrand-to-outpost-pi
created: 2026-07-02
updated: 2026-07-03
tags: [rebrand, fork-posture, epic]
---

# Rebrand the fork: remote_pi → Outpost-Pi

## Why rebrand

This checkout is a private fork of `jacobaraujo7/remote_pi` that has diverged
into a hard fork. As of 2026-07-02 the fork is **547 commits ahead, 0 upstream
commits since the fork point** (merge-base `02b2c92`, 2026-06-27), with
**+91,510 / −25,374 across 834 files** vs upstream. Of that, ~482 files are
private operator infrastructure (`.work/`, `.research/`, `.agents/`,
`.orchestration/`) that the upstream would never absorb; the product-code
divergence is roughly **+38,648 / −11,651 across ~236 product files** plus a
new `protocol/` generated-contract layer — architectural evolution, not a set
of patches.

With this much divergence and a hard-fork reality, keeping the name
"remote_pi" creates user confusion (which "remote pi"?) and a
credit/provenance tangle if the fork is ever released. The fork is robust and
cohesive enough that others may want to use it while it is maintained, so it
needs its own name now.

## The name: Outpost-Pi

**Outpost-Pi** — the outpost designated Pi (a la "Outpost Alpha").

- **The name is just the name.** Do NOT carry any military metaphor into the
  product: no forward-position / field-command / supply-line framing in docs,
  README, site copy, status labels, or design language. The word "outpost" in
  the name carries no operative meaning beyond being the product wordmark.
  (Operator stance, 2026-07-02.)

- Stays Pi-centric honestly: Pi is in the name, and the product is
  Pi-centric and will remain so (this is the Pi-native control surface).
- Distinct from upstream "remote_pi" — no name collision.
- Canonical casing: `Outpost-Pi` as the wordmark; `outpost-pi` lowercase for
  identifiers / CLI / npm.
- **npm availability confirmed clear** (2026-07-02): `outpost-pi`, `pi-tower`,
  `outpostpi` all 404 on the npm registry. GitHub repo name + domain to
  confirm separately.

## Licensing picture (MIT, permissive, single copyright holder)

- The only `LICENSE` in the tree is `pi-extension/LICENSE`: standard MIT,
  `Copyright (c) 2026 Jacob Moura`. Identical at the merge-base and on
  `upstream/main` — the fork did not add or modify it. No root LICENSE, no
  NOTICE, no per-file SPDX headers. The `app`, `relay`, `cockpit`, `site`
  subprojects have no license file and no license field (default: all rights
  reserved) — a latent issue to resolve as part of this rebrand, most likely by
  extending MIT to the whole repo since that's clearly the upstream intent.
- MIT permits rebranding, renaming, sublicensing, and releasing under a new
  name. One hard condition: **keep the copyright notice and the MIT permission
  text** in the distribution.
- Legal floor vs ethical bar:
  - Legal: keep `Copyright (c) 2026 Jacob Moura` + MIT text in a LICENSE file.
  - Ethical (operator stance, 2026-07-02): **credit the original author and
    project wherever it makes sense** — LICENSE, NOTICE, README. Add the
    operator's own copyright line for changes alongside, not replacing, the
    original. Do NOT scrub the upstream author from the provenance record.
- The ~65 product files referencing `jacobaraujo7` / `jacobmoura` (URLs,
  identifiers, the homepage `remote-pi.jacobmoura.work`) are not legally
  required to keep that text — those are identifiers, not the copyright
  notice. They can be rebranded freely; only the copyright line in the LICENSE
  must remain.

## Scope: four identifier classes (each handled differently)

1. **Code-internal strings (~200+)** — log prefixes like `[remote-pi]`, CLI
   command names, internal labels. Mechanically replaceable, but
   **protocol discriminators and the Android `applicationId` are
   wire/install-stable** and must NOT be renamed without a migration plan
   (changing them breaks pairing and forces an app reinstall).
2. **Package identifiers** — npm name (`remote-pi` → `outpost-pi`), Android
   `applicationId` (`work.jacobmoura.remotepi` → e.g.
   `dev.outpostpi.app`), iOS bundle id, the local-path extension registration
   in `~/.pi/agent/settings.json`. Changing the Android applicationId means
   existing installs cannot upgrade in place
   (`INSTALL_FAILED_UPDATE_INCOMPATIBLE` → uninstall + reinstall). One-time
   migration, not iterative.
3. **Provenance / authorship** — the 65 files referencing
   `jacobaraujo7`/`jacobmoura`. Keep the LICENSE copyright line; add a NOTICE
   crediting remote_pi / Jacob Moura as the foundation; do not scrub.
4. **External surfaces** — GitHub repo URL, homepage, npm publish target,
   site/marketing copy, branding assets. Downstream of the naming decision
   (now made); update last.

## EN-first scope (replace Portuguese with English)

- Replace PT with EN in all product code/docs/comments. The bulk is in
  `cockpit/` (~286 files with accented Latin / PT comments and strings).
- **Leave `scripts/` operator-glue shell comments untouched** unless
  explicitly asked — those are operator-facing automation glue, not shipped
  product; rewriting is churn without product value. (Boundary confirmed
  2026-07-02.)
- This is a separable workstream from the rename itself and can proceed in
  parallel or as a follow-up.

## Ordering (name decision is now made; this is the execution order)

1. ~~Pick a name~~ → **Outpost-Pi** (done).
2. Mechanical rename of code-internal strings (class 1, excluding
   wire/install-stable discriminators).
3. Migrate wire/install-stable identifiers carefully (class 2): protocol
   discriminators need a version-paired migration; Android applicationId
   change forces reinstall — gate on a release boundary.
4. Provenance (class 3): LICENSE keeps Jacob Moura copyright + adds operator
   line; add NOTICE; update README credit.
5. External surfaces (class 4): npm publish target, GitHub repo, homepage,
   branding.
6. EN-first pass (separable, parallel-able with 2–5).

## Relationship to other work

- **Not mentioned in this rebrand doc: Patchbay.** The fork may later consume
  Patchbay as its backend (replacing the relay/coordination layer), at which
  point the app/cockpit would retarget onto Patchbay's protocol client and the
  extension's session logic would move into a Patchbay Pi adapter. That is a
  future protocol migration, gated on Patchbay shipping a core + Pi adapter;
  it does not affect the fork's current naming. The Outpost-Pi name carries
  forward across that migration (it's the control-surface brand; the backend
  is an implementation detail the user never sees).
- The parity work (`roadmap-mobile-parity-with-pi-tui`) and the
  Patchbay-readiness work converge: keeping the control-surface /
  session-runtime separation clean (per parent finding
  `idea-mobile-conflates-transport-and-agent-state`) is *the same refactor*
  that makes the backend swappable onto Patchbay later. So the parity
  refactor pre-pays the Patchbay integration cost.

## Risk flags (do not lose)

- **Do not rename protocol discriminators or the Android applicationId
  without a migration plan** — they are stability boundaries, not cosmetic.
  The auth domain-separation and `to_room` requirement are already
  version-paired (see root `AGENTS.md` "Paired wire changes"); a discriminator
  rename would need the same treatment.
- **Do not scrub the upstream author** — keep provenance. A fork that
  rebrands but credits its origin is legitimate; one that hides it isn't,
  regardless of license.

## Not yet scoped (for `/agile-workflow:scope`)

This epic deliberately does not: decompose into features/stories, assign
`depends_on` chains, or sequence the identifier classes against release
boundaries. That's scope's job when the operator is ready to turn this into
tracked work.

## References

- Fork divergence baseline: merge-base `02b2c923a3263514f030d786ca10e6b1105b741b`
  (2026-06-27); HEAD 547 ahead, 0 upstream commits since; +91,510 / −25,374
  across 834 files; product-code subset +38,648 / −11,651 across ~236 files +
  new `protocol/` layer.
- `pi-extension/LICENSE` — the MIT file, `Copyright (c) 2026 Jacob Moura`.
- Root `AGENTS.md` — "Third-party fork posture" and "Paired wire changes".
- `roadmap-mobile-parity-with-pi-tui` — parity work; converges with
  Patchbay-readiness via the state-conflation refactor.
- `idea-mobile-conflates-transport-and-agent-state` — parent finding whose
  fix is the backend-swap enabler.
