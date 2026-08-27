---
id: story-resolve-speech-to-text-built-in-kotlin
kind: story
stage: done
tags: [app, deps, research]
parent: feature-stack-currency-review
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-27
updated: 2026-08-28
research_dials:
  scope_authority: pre-registered
  verification_rigor: floor
  intent: check current upstream built-in-Kotlin state and choose an upstream release, minimal fork, or replacement
  output_kind: item-local adoption decision and implementation rationale
---

# Resolve speech_to_text KGP blocker: upstream release vs minimal fork vs replacement

Decision story: check upstream for a built-in-Kotlin release; else evaluate minimal fork (KGP strip) vs replacement plugin. Decision + implementation recorded.

Findings, versions, and citations: feature-stack-currency-review.md (the
research item is the single source of truth for this migration program).
Note: story-unify-flutter-3-44-4-pins was completed at dormancy-setup time
(commit 80d9d8903: all four pins → 3.44.4) and is not spawned separately.

## Current upstream check (fetched 2026-08-28)

Decision relevance: if upstream now publishes a migrated package, use it and
avoid owning a fork; otherwise choose the least risky fork/replacement that
removes the final plugin blocker.

- The [pub package API](https://pub.dev/api/packages/speech_to_text) still names
  7.4.0 as latest stable, but now lists `7.5.0-beta.1`, published 2026-07-02.
- The fetched [7.5.0-beta.1 archive](https://pub.dev/api/archives/speech_to_text-7.5.0-beta.1.tar.gz)
  raises its floors to Flutter 3.44/Dart 3.12 and explicitly records the
  built-in-Kotlin migration. Its Android build removes `kotlin-android` and old
  `kotlinOptions`, retaining `kotlin.compilerOptions` at JVM 17.
- Upstream [`main` Android build](https://github.com/csdcorp/speech_to_text/blob/main/speech_to_text/android/build.gradle),
  [`pubspec.yaml`](https://github.com/csdcorp/speech_to_text/blob/main/speech_to_text/pubspec.yaml),
  and [`CHANGELOG.md`](https://github.com/csdcorp/speech_to_text/blob/main/speech_to_text/CHANGELOG.md)
  match the published beta. The repository was last pushed immediately after
  that beta publication.

## Decision and rationale

**Adopt upstream `speech_to_text` 7.5.0-beta.1 as an exact prerelease pin.**

The upstream state moved after the parent review: the required migration now
exists as a hosted package, so a private fork would duplicate the same small
Gradle change while adding carry, trust, and update-tracking costs. Replacing the
plugin would be still riskier because Outpost-Pi depends on its locale discovery,
on-device recognition option, sound-level stream, and mature Android/iOS
behavior. The exact prerelease pin contains beta risk and makes the revisit
condition explicit: move to stable 7.5+ once it carries the same migration.

### Disconfirming analysis

- Stable 7.4.0 remains unmigrated; leaving the existing `^7.0.0` constraint
  would continue selecting it and does not clear the blocker.
- The adopted build is a beta, not a stable release. That weighs against a
  floating prerelease range, but not against the exact pin because its changelog
  contains only the SDK-floor/Kotlin migration and the existing SpeechService
  seam exercises the Dart API independently of platform channels.
- A minimal fork remains technically possible, but offers no functional or
  schedule advantage over the fetched upstream artifact. Replacement remains
  disproportionate absent a product defect in speech behavior.

## Implementation notes

- Execution capability: inline implementation plus a focused, source-direct
  current-state check; one dependency and its existing adapter/tests.
- Review weight: standard default for implementation; child-story checkpoint
  review is not applicable after green verification.
- Files changed: speech dependency/lock and loaded-suite timing fixtures.
- Tests added/removed: none for speech; the existing service/ViewModel/widget
  tests cover locale, transcript, permission, cancel, timer, and UI contracts.
  Loaded-suite fixtures gained bounded convergence headroom without weakening
  behavioral assertions.
- Simplification: no fork, git dependency, carry patch, replacement adapter, or
  upstream-tracking file was needed.
- Discrepancies from design: the previously absent upstream option is now
  available as a prerelease rather than stable.
- Adjacent issues parked: none.

## Research engagement record

- Registration: pre-registered one-facet light path; consumer = app KGP
  migration chain; temporal contract = current upstream state on 2026-08-28;
  primitives extended/opted out = none; analytical artifact = item-local
  adoption decision.
- Floor verification: pub metadata, the exact hosted archive, and upstream main
  were fetched and compared; a disconfirming pass checked stable-vs-beta risk,
  fork cost, and replacement scope. No source contradiction remains.

## Closure evidence

- `speech_to_text`: 7.4.0 → exact upstream 7.5.0-beta.1.
- `flutter analyze`: no issues.
- Targeted speech service/ViewModel/widget tests: 33 passed.
- Full app suite (`--exclude-tags e2e --concurrency=2`): 987 passed.
