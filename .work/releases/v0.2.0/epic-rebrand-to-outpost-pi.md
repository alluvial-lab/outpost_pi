---
id: epic-rebrand-to-outpost-pi
kind: epic
stage: done
tags: [rebrand, fork-posture, pi-extension, app, relay, cockpit, site, docs]
parent: null
depends_on: []
release_binding: v0.2.0
gate_origin: null
created: 2026-07-02
updated: 2026-07-20
---

# Rebrand the fork: remote_pi → Outpost-Pi

## Why rebrand

This checkout is a private fork of `jacobaraujo7/remote_pi` that has diverged
into a hard fork. As of 2026-07-02 the fork is **547 commits ahead, 0 upstream
commits since the fork point** (merge-base `d6be6a4`, 2026-06-27), with
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

## Decomposition

Split by the four identifier classes the epic already named, each becoming
one child feature. The slices are intentionally disjoint so they can proceed
in parallel: the mechanical rename's exclusion list is the contract that
keeps it off the wire-stable literals the migration feature owns. The
breaking slice (wire + install-stable + version reset) is the only one
gated on a release boundary — everything else is non-breaking. External
surfaces (class 4) move to a follow-up epic per the locked strategic
decision.

### Child features

- `epic-rebrand-to-outpost-pi-mechanical-rename` — code-internal
  `remote_pi`/`remote-pi` strings → `outpost-pi`/`Outpost-Pi` (~1,613 occ /
  ~240 files across all 5 subprojects); excludes wire-stable literals —
  depends on: `[]`
- `epic-rebrand-to-outpost-pi-wire-and-install-stable-migration` — the
  breaking 0.1.0 slice: auth string → `outpost-pi-relay-auth-v1`, control-RPC
  discriminator → `outpost-pi-ctrl`, applicationId/bundle →
  `dev.kevoun.outpostpi`, version reset to 0.1.0 across all manifests;
  hard-cutover, version-paired release — depends on: `[]` (coordinate at
  release time with the mechanical rename; no hard type dependency)
- `epic-rebrand-to-outpost-pi-provenance` — root LICENSE (extend MIT to whole
  repo, keep Jacob Moura copyright + add operator line), root NOTICE, README
  credit; no code behavior change — depends on: `[]`
- `epic-rebrand-to-outpost-pi-en-first` — PT → EN in shipped product
  (cockpit-heavy, ~186 files); `scripts/` operator glue explicitly excluded.
  **Scoped out to follow-up** (`.work/backlog/`) — separable from the rename,
  does not block 0.1.0.

### Decomposition risks

- **Cross-slice string collision.** The mechanical rename and the wire-stable
  migration both touch `remote-pi*` literals. The risk is the mechanical
  rename accidentally rewriting a wire-stable constant (`remote-pi-relay-auth`,
  `remote-pi-ctrl`, `jacobmoura.remotepi`) out of sequence, creating a
  half-migrated wire surface. Mitigation: the mechanical-rename feature's
  exclusion list is the explicit contract; the design pass should use a
  scripted replacement with the exclusion list and verify zero unintended
  wire-stable edits via grep.
- **Release-time coordination despite no hard dependency.** The mechanical
  rename and the wire-stable migration have no `depends_on` edge and can
  develop in parallel, but they must ship in the same 0.1.0 release or the
  released artifact is inconsistently named (cosmetic strings say
  Outpost-Pi but wire/applicationId still say remote-pi, or vice versa).
  This is a release-binding concern, handled at `/agile-workflow:release-deploy`
  time, not a `depends_on` edge.
- **applicationId change is irreversible on the phone.** After the first
  0.1.0 sideload there is no path back to `work.jacobmoura.remotepi` without
  another uninstall. The wire-stable migration feature's design pass must
  verify the chosen `dev.kevoun.outpostpi` identifier before shipping.
- **AGENTS.md / PROTOCOL.md / CHANGELOG.md drift.** These durable docs
  reference the old auth string and old paired versions. They must be rolled
  forward in-place to the new `outpost-pi-relay-auth-v1` and `0.1.0` pairing
  as part of the wire-stable migration (rolling-foundation: current truth,
  no migration prose).

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

## Strategic decisions (locked 2026-07-11)

These directional choices were resolved at scope time and set the frame for
`/agile-workflow:epic-design` decomposition and the foundation-doc
roll-forward.

- **Versioning — Outpost-Pi 0.1.0 across all subprojects.** The rebrand is
  the inception of Outpost-Pi as a named product and the natural reset point
  to align all subprojects at a pre-1.0 0.x line. The product is *not* a
  stable v1: v0.6.0 shipped with the `/remote-pi pair` flow broken, a
  fundamental session-replacement lifecycle bug was only just fixed
  (`feature-session-stable-message-delivery`), and the phone side is still
  observability-blind with unreproduced reconnect-cluster bugs. Cutting 1.0
  would overstate stability; 0.x honestly signals "expect breaking changes."
  App (1.2.0+7) and cockpit (1.5.1+9) bump *down* to 0.1.0; semver does not
  forbid this and the rebrand is the natural reset moment. Extension
  (0.6.0) and relay (0.2.2) reset to 0.1.0; site and rp-s3 stay 0.1.0. The
  547-commit history stays in git + NOTICE as provenance, not a
  version-number claim.
- **Paired-wire story — `app-0.1.0 ↔ relay-0.1.0 ↔ extension-0.1.0`.**
  All three ship together as one breaking release; mixed versions break (same
  discipline as the prior pre-rebrand paired-wire releases, whose tags were
  deleted at the 0.1.0 reset; retained bodies remain under
  `.work/releases/`).
- **Auth domain string — rename in place to `outpost-pi-relay-auth-v1\n`,
  keep v1.** The literal is renamed but the version suffix stays `v1`. Bumping
  to `v2` would be semver noise; the wire boundary moved with the version
  reset to 0.1.0, which is the honest signal that the compatibility surface
  broke. The renamed constant appears in app (`ws_transport.dart`),
  extension (`relay_client.ts`), relay (`challenge.rs`), and docs.
- **Cockpit↔pi control RPC discriminator — also renamed, same release.** The
  NUL-prefixed control string `\x00remote-pi-ctrl:<method>:<args...>` is a
  third wire-stable identifier (schema-defined in
  `protocol/schema/cockpit-control.schema.json`, emitted by the extension
  `CTRL_PREFIX` constant, consumed by cockpit). It is renamed to
  `\x00outpost-pi-ctrl:...` on the same hard-cutover release. This is the
  cockpit↔extension control path, distinct from the app↔relay↔extension
  auth pairing, but governed by the same no-dual-accept rule.
- **Backwards compatibility — hard cutover.** The new relay accepts *only*
  the new auth string; old app/extension versions are rejected immediately.
  The fork is single-operator with one phone, so coordination cost is low and
  a dual-accept transition window adds complexity without benefit. No
  dual-auth window, no deprecated-but-accepted path.
- **Application / bundle identifiers — `dev.kevoun.outpostpi`.**
  - Android app `applicationId`: `work.jacobmoura.remotepi` →
    `dev.kevoun.outpostpi`
  - iOS `PRODUCT_BUNDLE_IDENTIFIER`: `work.jacobmoura.remotepi.app` →
    `dev.kevoun.outpostpi.app`
  - `remote_pi_identity` plugin Android namespace:
    `dev.remotepi.identity` → `dev.kevoun.outpostpi.identity`
  - `kevoun.com` is the org identifier (reverse-DNS convention; the domain
    is never resolved at runtime — purely a uniqueness identifier). Using
    the operator's own domain is cleaner than retaining the upstream
    `work.jacobmoura.*` being moved away from.
  - Phone-side consequence is a one-time uninstall + reinstall (existing
    install cannot upgrade in place: `INSTALL_FAILED_UPDATE_INCOMPATIBLE`).
    Single operator, single phone, one-time cost.
- **External surfaces (class 4) — deferred to a follow-up epic.** GitHub
  repo rename (`remote_pi` → `outpost-pi`), npm publish target
  (`outpost-pi`), homepage, branding assets, and site/marketing copy are
  *not* part of this epic. This epic ships the code rename + provenance +
  wire/applicationId migration. External identity moves separately. The
  extension is registered local-path in `~/.pi/agent/settings.json`, so npm
  publishing is decoupled from the code rename landing.
- **EN-first — separable, parallel-able workstream.** Replacing Portuguese
  with English (bulk in `cockpit/`, ~186 files with accented Latin) is a
  distinct workstream from the rename. It can proceed in parallel or as a
  follow-up. `scripts/` operator-glue shell comments are explicitly left
  untouched (operator-facing automation glue, not shipped product).

## Decomposition (for `/agile-workflow:epic-design`)

Not yet decomposed into features/stories with `depends_on` chains. The natural
seam is the four identifier classes, sequenced against the 0.1.0 release
boundary:

1. **Mechanical rename** (class 1, code-internal strings) — the bulk
   (~1,822 occurrences / 264 files), safe, non-breaking.
2. **Wire + install-stable migration** (class 2) — the breaking slice: auth
   string rename, applicationId/bundle id, version reset to 0.1.0. Gated on
   the paired release.
3. **Provenance** (class 3) — LICENSE + NOTICE + README credit; root LICENSE
   extended MIT to the whole repo.
4. **EN-first** (parallel) — Portuguese → English in shipped product,
   cockpit-heavy.

External surfaces (class 4) move to a follow-up epic.

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

## Epic review (2026-07-12)

**Verdict**: Approve — rebrand core scope complete

**Summary**: The Outpost-Pi rebrand is implemented and reviewed. All 3 in-scope
child features are done (mechanical-rename, wire-stable migration, provenance).
The en-first feature (PT→EN) was scoped out to a follow-up
(`.work/backlog/epic-rebrand-to-outpost-pi-en-first.md`) — it was always framed
as separable from the rename and doesn't block the 0.1.0 release. The
rebrand's core scope — name, wire-stable identifiers, install identifiers,
storage/keyring/launchd, provenance, version reset to 0.1.0, durable docs —
is complete and review-converged.

**Blockers**: none (all deep-review blockers fixed inline across 2 phases)
**Important**: 5 backlog items filed (README acknowledgements, branding SVG
redraw, cross-client auth test, site download links, WinSparkle marketing-version
comparison) — none blocking the 0.1.0 code release.

**Scoped out (follow-up)**: en-first feature (PT→EN translation, cockpit-heavy).
External surfaces (GitHub repo rename, npm publish, branding) — follow-up epic.

**Notes**: Deep-lane epic review. The fresh-context reviewer (gpt-5.6-sol)
found real issues the implementation missed (build-number semantics,
half-renamed fixture, stale agent-skill reference, deploy-runbook ambiguity)
— all fixed. 54 commits ahead of origin/main, tree clean. Ready for release
cut once the operator confirms the deploy order (relay → Pi restart → app →
cockpit) and accepts the destructive cutover (phone reinstall + re-pair +
old-daemon cleanup).

## Follow-up scope (2026-07-14)

A post-epic coherence review found active pre-rebrand identifiers that the
original review should have caught. The epic is reopened while
`feature-outpost-pi-identifier-convergence` completes canonical protocol,
code/test alias, contract-test, and stateful runtime identifier convergence.
Intentional provenance, history, legacy-rejection evidence, and checkout-path
migration remain explicitly outside that feature. The parallel
`story-root-readme-provenance-acknowledgement` completes the README credit that
the original provenance feature promised but missed.
