---
id: backlog-ci-pin-deps-audit-e2e-pairing-refs
created: 2026-08-11
updated: 2026-08-11
tags: [workflow, security]
---

# Pin mutable GitHub Actions refs in deps-audit.yml and e2e-pairing.yml

## Origin

Deferred residual of `gate-security-ci-mutable-action-refs`. That story's
assigned write scope was `ci.yml` only (which was pinned); the finding also
named `.github/workflows/deps-audit.yml` and `.github/workflows/e2e-pairing.yml`,
documented in-body as "requires separately scoped follow-up" — but the follow-up
was never re-tracked. This item captures it so the deferral stops leaking out of
the tracking system.

## Location

- `.github/workflows/deps-audit.yml:33-57`
- `.github/workflows/e2e-pairing.yml:24-40`

## Severity

Medium — supply-chain. Mutable `@v4` / `@v2` / `@cargo-audit` action refs are
vulnerable to upstream tag re-pointing; pinning to a commit SHA removes that
class of compromise.

## Work

Pin each third-party action ref in both workflows to a commit SHA, matching the
treatment already applied in `ci.yml`. Note the pinned digest in a comment so
future bumps are deliberate.
