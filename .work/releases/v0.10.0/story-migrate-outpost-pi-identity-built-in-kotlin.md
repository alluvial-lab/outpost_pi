---
id: story-migrate-outpost-pi-identity-built-in-kotlin
kind: story
stage: done
tags: [app, deps]
parent: feature-stack-currency-review
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-27
updated: 2026-08-28
---

# Migrate outpost_pi_identity (owned) off legacy KGP to built-in Kotlin

Full built-in-Kotlin migration for our own plugin: KGP removal, compiler-options migration, SDK floor updates, example-app migration, dual-mode build tests. Research §3.1 for the treatment.

Findings, versions, and citations: feature-stack-currency-review.md (the
research item is the single source of truth for this migration program).
Note: story-unify-flutter-3-44-4-pins was completed at dormancy-setup time
(commit 80d9d8903: all four pins → 3.44.4) and is not spawned separately.

## Implementation notes

- Execution capability: inline implementation; the owned plugin, its example,
  and both lockfiles form one cohesive migration boundary.
- Review weight: standard default; child-story checkpoint review is not
  applicable after green verification.
- Files changed: plugin/example Gradle and SDK metadata, changelog, and root +
  example lockfiles.
- Tests added/removed: none; existing plugin tests and both Android consumer
  builds exercise the stable public and build integration surfaces.
- Simplification: removed the owned plugin's KGP classpath/application and old
  `kotlinOptions`; the example uses the compiler-options DSL and limits its KGP
  application to the checked-in AGP 8 legacy path.
- Discrepancy from design: Flutter 3.44.4 cannot enable built-in Kotlin; official
  true-mode execution requires Flutter 3.47+ and AGP 9. The pinned legacy-mode
  example and root APKs both build, and the root warning inventory no longer
  names `outpost_pi_identity`; the true-mode APK remains the explicit next
  AGP-9/app-flip story gate rather than silently flipping this app early.
- Adjacent issues parked: none.

## Closure evidence

- `flutter analyze`: no issues.
- Full app suite (`--exclude-tags e2e --concurrency=2`): 984 passed.
- Plugin suite: 17 passed; example analyze: no issues.
- Example and root debug APKs built on Flutter 3.44.4/AGP 8 legacy mode.
- Root APK warning inventory excludes the owned plugin.
