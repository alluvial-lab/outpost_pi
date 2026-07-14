---
id: epic-rebrand-external-surfaces-retire-rp-s3-cross-surface-verification
kind: story
stage: implementing
tags: [rebrand, app, cockpit, site, rp-s3]
parent: epic-rebrand-external-surfaces-retire-rp-s3
depends_on: [epic-rebrand-external-surfaces-retire-rp-s3-runtime-update-noop, epic-rebrand-external-surfaces-retire-rp-s3-site-manifest-fallback, epic-rebrand-external-surfaces-retire-rp-s3-dormant-server-docs]
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Verify rp-s3 retirement across every owned surface

Run only after the three implementation stories complete.

## Scope

- Search tracked product source for `rp-s3.jacobmoura.work`,
  `jacobmoura7/rp-s3`, and `/Users/flutterando`; correct only residual matches
  owned by this feature. Exclude ignored/generated `site/.next/` output.
- Run app and cockpit `flutter analyze` plus relevant focused tests. Run the
  applicable site static check and Compose validation when their tools are
  available.
- Confirm that `site/src/lib/{app,cockpit}-release.ts` still has any
  F2-owned `outpost-pi.jacobmoura.work` mock artifact URLs untouched. Report
  those as intentional sibling ownership, not residual rp-s3 work.

## Acceptance criteria

- [ ] No tracked source retains the retired rp-s3 hostname, Docker namespace,
  or Jacob VPS paths.
- [ ] Required verification results or exact environment blockers are recorded.
- [ ] No F2 hostname-migration scope is absorbed.
