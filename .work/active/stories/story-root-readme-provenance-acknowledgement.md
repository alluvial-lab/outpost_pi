---
id: story-root-readme-provenance-acknowledgement
kind: story
stage: review
tags: [rebrand, docs, legal]
parent: epic-rebrand-to-outpost-pi
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-12
updated: 2026-07-14
---

# Correct root README provenance and license status

## Brief

Complete the ethical provenance commitment locked by the rebrand epic and correct the README's stale license statement. `LICENSE` and `NOTICE` already establish the repository-wide MIT license and preserve the upstream copyright and foundation, but the root README still lacks the promised acknowledgement and incorrectly says that licensing is per-package with a repository-wide decision pending.

Make both adjacent corrections:

- add a concise “Acknowledgements” or “Based on” section crediting [`remote_pi`](https://github.com/jacobaraujo7/remote_pi) and Jacob Moura as the MIT-licensed foundation on which Outpost-Pi was built;
- rewrite the README **License** section to state that Outpost-Pi is licensed repository-wide under the root MIT `LICENSE`, without implying that the decision remains pending.

Match the factual tone of `NOTICE`; do not imply current operational ownership, distribution identity, or endorsement by the upstream author. These intentional provenance occurrences are part of the keep-list for product-identifier cleanup.

## Implementation notes
- Files changed: `README.md`
- Added an **Acknowledgements** section crediting `remote_pi` / Jacob Moura as the MIT-licensed foundation.
- Rewrote the **License** section from the stale "per-package, repository-wide decision pending" text to state repository-wide MIT under root `LICENSE`.
- Discrepancies from design: none.
- Adjacent issues parked: none.
