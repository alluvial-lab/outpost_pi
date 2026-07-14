---
id: epic-rebrand-external-surfaces-retire-rp-s3-cross-surface-verification
kind: story
stage: review
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

- [x] No tracked source retains the retired rp-s3 hostname, Docker namespace,
  or Jacob VPS paths.
- [x] Required verification results or exact environment blockers are recorded.
- [x] No F2 hostname-migration scope is absorbed.

## Implementation notes

- The tracked-source scan found no `rp-s3.jacobmoura.work`,
  `jacobmoura7/rp-s3`, or `/Users/flutterando` matches outside transient work
  records and generated output. The scan covered the owned product and CI
  surfaces (`.github`, `app`, `cockpit`, `pi-extension`, `relay`, `site`, and
  `rp-s3`) while excluding `.work/`, `.research/`, and ignored `site/.next/`.
- The scan exposed stale rp-s3 publication instructions in the tracked app and
  Cockpit release workflows. Those are F3-owned operational references, so they
  were corrected to describe the current disabled-manifest/appcast state. No
  F2 hostname migration was folded into this change.
- F2-owned mock artifact/fallback hostname lines were deliberately not edited by
  this story. They were present in the dependency baseline in
  `site/src/lib/cockpit-release.ts` and `app/lib/ui/update/viewmodels/update_banner_viewmodel.dart`;
  concurrent F2 working-tree changes are outside this commit. Their ownership
  is intentional and does not represent residual rp-s3 work.

## Verification

- `which flutter` → `/home/agent/projects/remote_pi/.tools/flutter/bin/flutter`.
- `flutter analyze` passed in both `app/` and `cockpit/` with the repository
  pub cache configured; no rp-s3-owned analyzer errors were present.
- Focused update tests passed: app `test/domain/update_info_test.dart` and
  `test/ui/update/update_banner_viewmodel_test.dart`; Cockpit
  `test/domain/update_info_test.dart` and
  `test/data/auto_updater_self_updater_test.dart`.
- From `site/`, the required writable-cache `corepack pnpm lint && corepack
  pnpm build` passed. pnpm emitted only the known unreadable `/home/agent/.npmrc`
  and deprecated package-level `pnpm.onlyBuiltDependencies` warnings.
- `docker compose -f rp-s3/docker-compose.yml config -q` passed.
