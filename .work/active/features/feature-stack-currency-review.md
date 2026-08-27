---
id: feature-stack-currency-review
kind: feature
stage: implementing
tags: [research, workflow]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-27
updated: 2026-08-27
research_dials:
  scope_authority: pre-registered
  verification_rigor: standard
  intent: audit toolchain/dependency currency across all five subprojects; produce a prioritized migration plan (flutter pin, KGP, dep debt, rust/node/next/pi-sdk) feeding implementation stories
  output_kind: findings + prioritized plan in this body; child stories spawned for executable migrations
---

# Stack currency review (architecture/tool/stack choice audit)

Operator-triggered 2026-08-27 after v0.9.0 ship ("clean basis"). Motivating
evidence from the v0.9.0 cycle:

- Flutter pin drift: CI 3.41.7 vs local-build 3.44.4 vs stable 3.47.1;
  rc/final artifacts built by 3.44.4.
- KGP migration deadline: 9 plugins apply legacy Kotlin Gradle Plugin
  (incl. OWNED outpost_pi_identity); AGP 10 kills the opt-out (expected
  2026). Flutter 3.47 enables built-in Kotlin post-migration.
- 40 pub packages constrained behind newer incompatible versions.
- Stale-IME engine bug NOT the long-fixed #118761 — root-cause class still
  open upstream; unknown whether 3.47 fixes ours.
- No toolchain audit this cycle for relay (rust), site (node/next),
  extension (node/pi SDK), cockpit (macos/windows min-targets vs 3.47's
  iOS15/macOS12 floors).

## Engagement scope (pre-registered)

1. Flutter: 3.41.7→3.47.1 upgrade assessment (breaking changes, plugin
   compat incl. the 9 KGP plugins, whether 3.47 changes the stale-IME
   behavior), pin-unification plan (CI == local == release).
2. KGP: built-in-Kotlin migration for outpost_pi_identity (ours, now) +
   upstream tracking matrix for the 8 third-party.
3. Dependency-freshness pass: pub constraints audit (the 40), cargo audit
   + rustc toolchain, package.json/node LTS + next major, pi SDK pin.
4. Output: prioritized migration plan → child stories with depends_on
   ordering; quick wins flagged (CI pin alignment).

## Research engagement record (2026-08-27)

- **Registered dials honored:** `scope_authority: pre-registered`,
  `verification_rigor: standard`; focused single-pass, item-local output.
- **Decision relevance:** decide whether to pin Flutter now or treat 3.47 as a
  migration project, and turn verified dependency/toolchain debt into ordered
  implementation stories rather than an undifferentiated upgrade sweep.
- **Registration remainder:** consumer = Outpost-Pi implementation planning;
  temporal contract = current-version audit as of 2026-08-27; analytical
  artifact type = findings plus adoption recommendations; no primitive
  extensions or opt-outs.
- **Output constraint:** the commissioning contract permits writing only this
  item, so the fetched-source attestations below are item-local rather than
  separate `.research/attestation/` files.

## Source attestations

All sources below were fetched on 2026-08-27 before the findings were authored.
The numbered statements are the only web-source claims used by the synthesis.

- **`flutter-breaking-index`** — [Flutter breaking-change index](https://docs.flutter.dev/release/breaking-changes):
  {1} the 3.44 list contains the menu-close-order, reorder callback,
  `TextInputConnection.setStyle`, cache-extent, `IconData`, Android large-screen,
  `ListTile`, built-in-Kotlin, and page-transition changes; {2} the 3.47 list
  contains OpenGL render-texture orientation, semantics heading behavior, and
  removal of `describeEnum`.
- **`flutter-describe-enum`** — [`describeEnum` detail page](https://docs.flutter.dev/release/breaking-changes/remove-describeEnum):
  {1} the method is described as removed, but the page's own timeline still
  labels both landed and stable versions `TBD`.
- **`flutter-bik`** — [Flutter built-in-Kotlin overview](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin):
  {1} AGP 9 defaults to built-in Kotlin and explicitly applying KGP is
  incompatible; {2} Flutter 3.44 supports the temporary
  `android.builtInKotlin=false` path, while Flutter 3.47 supports enabling it
  after the app and every plugin migrate; {3} the new AGP DSL is a distinct
  migration from KGP.
- **`flutter-plugin-bik`** — [Flutter plugin-author migration guide](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors):
  {1} remove `kotlin-android` and `kotlinOptions`, then configure
  `kotlin.compilerOptions`; {2} the straightforward path raises minimums to
  Flutter 3.44 and Dart 3.12; {3} a compatibility path conditionally applies
  KGP only below AGP 9; {4} validating with `android.builtInKotlin=true`
  requires Flutter 3.47 or later.
- **`flutter-app-bik`** — [Flutter app-developer migration guide](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers):
  {1} Flutter currently adds `android.builtInKotlin=false` and
  `android.newDsl=false`; {2} app migration removes KGP and old
  `kotlinOptions`, adds compiler options, moves to AGP 9+, and validates with
  the built-in-Kotlin flag true.
- **`android-agp9`** — [Android Gradle Plugin 9.0 release notes](https://developer.android.com/build/releases/agp-9-0-0-release-notes):
  {1} AGP 9 enables built-in Kotlin and the new DSL by default; {2} the
  documented AGP 10 removal warning applies to the **old-DSL** opt-out
  `android.newDsl=false`; the page does not say that AGP 10 removes
  `android.builtInKotlin=false`.
- **`flutter-344-notes`** — [Flutter 3.44 release notes](https://docs.flutter.dev/release/release-notes/release-notes-3.44.0):
  {1} keyboard-related entries are a web IME/selection fix, Android
  `FocusHighlightMode` behavior, and an iOS keyboard-flicker fix.
- **`flutter-347-notes`** — [Flutter 3.47 release notes](https://docs.flutter.dev/release/release-notes/release-notes-3.47.0):
  {1} keyboard/inset entries are an iOS keyboard-inset refactor and a Windows
  Korean-IME caret fix; {2} the notes do not identify an Android stale
  WindowManager IME-inset fix.
- **`flutter-platforms`** — [Flutter supported deployment platforms](https://docs.flutter.dev/reference/supported-platforms):
  {1} iOS support starts at 15; {2} macOS support starts at Monterey 12;
  {3} Windows support is 10 and 11.
- **`pub-app-settings`** — [pub API](https://pub.dev/api/packages/app_settings)
  and [changelog](https://pub.dev/packages/app_settings/changelog): {1} latest
  is 9.0.0; built-in-Kotlin compatibility is present from 8.0.3.
- **`pub-image-compress`** — [pub API](https://pub.dev/api/packages/flutter_image_compress_common)
  and [changelog](https://pub.dev/packages/flutter_image_compress_common/changelog):
  {1} latest is 1.1.1; 1.1.0 introduced the built-in-Kotlin migration and 1.1.1
  corrected Gradle-9 mode handling.
- **`pub-image-picker`** — [pub API](https://pub.dev/api/packages/image_picker_android)
  and [changelog](https://pub.dev/packages/image_picker_android/changelog):
  {1} latest is 0.8.13+19; 0.8.13+18 migrated to built-in Kotlin.
- **`pub-mobile-scanner`** — [pub API](https://pub.dev/api/packages/mobile_scanner)
  and [7.4.0 Android build file](https://github.com/juliansteenbakker/mobile_scanner/blob/v7.4.0/android/build.gradle):
  {1} 7.4.0 is latest and conditionally avoids applying KGP when AGP 9
  built-in Kotlin is active.
- **`pub-package-info`** — [pub API](https://pub.dev/api/packages/package_info_plus)
  and [changelog](https://pub.dev/packages/package_info_plus/changelog):
  {1} latest is 10.2.1; 10.2.0 added built-in-Kotlin support.
- **`pub-share`** — [pub API](https://pub.dev/api/packages/share_plus) and
  [changelog](https://pub.dev/packages/share_plus/changelog): {1} latest is
  13.3.0; 13.2.0 added built-in-Kotlin support.
- **`pub-speech`** — [pub API](https://pub.dev/api/packages/speech_to_text),
  [7.5.0-beta.1 archive](https://pub.dev/api/archives/speech_to_text-7.5.0-beta.1.tar.gz),
  and [upstream main](https://github.com/csdcorp/speech_to_text): {1} 7.4.0 is
  still the latest stable and directly applies `kotlin-android`; {2} the versions
  list also contains 7.5.0-beta.1, whose Android build removes KGP and uses
  `kotlin.compilerOptions` with Flutter 3.44/Dart 3.12 floors (correction
  2026-08-28: the original pass checked only the API's latest-stable object).
- **`pub-url-launcher`** — [pub API](https://pub.dev/api/packages/url_launcher_android)
  and [changelog](https://pub.dev/packages/url_launcher_android/changelog):
  {1} latest is 6.3.32; 6.3.31 migrated to built-in Kotlin.
- **`node-schedule`** — [Node release schedule](https://raw.githubusercontent.com/nodejs/Release/main/schedule.json):
  {1} Node 22 entered maintenance in 2025 and ends support in 2027; Node 24 is
  LTS and does not enter maintenance until 2026-10-20; Node 26 does not become
  LTS until 2026-10-28.
- **`npm-next`** — [Next npm metadata](https://registry.npmjs.org/next/latest):
  {1} latest is 16.3.3 and requires Node `>=20.9.0`; there is no newer stable
  major in the registry.
- **`npm-pi`** — [Pi 0.80.6 metadata](https://registry.npmjs.org/@earendil-works%2Fpi-coding-agent/0.80.6),
  [latest metadata](https://registry.npmjs.org/@earendil-works%2Fpi-coding-agent/latest),
  and [upstream changelog](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/CHANGELOG.md):
  {1} the current and latest SDK both require Node `>=22.19.0`; {2} latest is
  0.84.3; {3} intervening breaking changes include removal of `AuthStorage` in
  0.80.8, TypeBox removals in 0.83, and 0.84 changes to `message_update` and
  `ModelRegistry.refresh()`.
- **`crates-current`** — fetched crates.io metadata for
  [axum](https://crates.io/api/v1/crates/axum),
  [ed25519-dalek](https://crates.io/api/v1/crates/ed25519-dalek),
  [rand](https://crates.io/api/v1/crates/rand), and
  [reqwest](https://crates.io/api/v1/crates/reqwest): {1} current stable majors
  are respectively 0.8.9, 3.0.0, 0.10.2, and 0.13.4.

## Findings

### 1. Flutter 3.41.7 → 3.47.1 assessment

**Recommendation: pin 3.44.4 immediately; make 3.47.1 the next migration target,
not today's pin.** {inferred: recommendation} The release-building SDK is already the repo-local Flutter
3.44.4/Dart 3.12.2 tool (`.agents/skills/flutter-mobile/SKILL.md:43-56`; confirmed
with `.tools/flutter/bin/flutter --version` and exact Git tag `3.44.4`), while
all checked-in Flutter CI/release pins still say 3.41.7
(`.github/workflows/app-release.yml:29-32`, `.github/workflows/ci.yml:15-17`,
`.github/workflows/cockpit-release.yml:28-31`,
`.github/workflows/e2e-pairing.yml:14-16`). Pinning 3.47.1 before resolving KGP
and deployment-floor work would combine a reproducibility fix with a platform
migration.

The official breaking-change inventory adds nine 3.44 entries and three 3.47
entries.[flutter-breaking-index]{1} [flutter-breaking-index]{2} A targeted source
scan found no `TextInputConnection.setStyle`, Flutter `onReorder` API,
`cacheExtent`, `extends IconData`, `describeEnum`, `Semantics(header: true)`, or
custom fragment-shader use in `app/lib` or `cockpit/lib`; Cockpit's occurrences
of `onReorder` are its own typed project-order callback
(`cockpit/lib/app/cockpit/ui/widgets/projects_rail.dart:62-63,748-767`). Thus the
known source-level migration is Android/Kotlin rather than those Dart APIs. The
3.44 `ListTile` debug assertion and Android large-screen policy still warrant
normal widget/device regression tests; absence of a named API call does not
prove behavior is unchanged.

**Cockpit/platform floor.** Flutter 3.47 supports macOS 12+ and Windows 10/11.
[flutter-platforms]{2} [flutter-platforms]{3} Cockpit currently declares macOS
10.15 in CocoaPods and all Xcode configurations
(`cockpit/macos/Podfile:1`,
`cockpit/macos/Runner.xcodeproj/project.pbxproj:570,652,702`) and publishes an
appcast minimum of 10.15 (`.github/workflows/cockpit-release.yml:378-390`). A
3.47 migration must raise all of those to 12 in the same change and explicitly
accept dropping Catalina/Big Sur. No Windows deployment-floor edit is indicated.
The mobile app already targets iOS 18 (`app/ios/Podfile:1-2`), so Flutter's iOS
15 floor is below its existing floor.[flutter-platforms]{1}

**IME/inset result.** There is no release-note evidence that 3.47 fixes this
app's Android stale-inset class. The relevant 3.44 entries concern web, Android
focus-highlight mode, and iOS flicker; 3.47 names iOS inset refactoring and a
Windows Korean-IME caret fix, not Android stale WindowManager insets.
[flutter-344-notes]{1} [flutter-347-notes]{1} [flutter-347-notes]{2} The local
workaround is specifically for Pixel Fold retaining `viewInsets.bottom` after
focus/IME departure and uses an independent native visibility probe plus a
four-second watchdog (`app/lib/routing/adaptive.dart:115-150,228-259`), with a
regression that requires `TextInput.hide` only after the grace interval
(`app/test/routing/adaptive_test.dart:291-357`). Keep it through the upgrade and
make physical Pixel Fold posture/keyboard UAT an acceptance criterion; removal
requires a reproduced 3.47 device result, not release-note inference.

**Upgrade shape.** Move directly from the real 3.44.4 baseline to 3.47.1 after
blockers clear; there is no value in manufacturing 3.45/3.46 pin steps.
{inferred: sequencing} The
safe sequence is: (a) unify at 3.44.4; (b) migrate owned and third-party plugins
while `android.builtInKotlin=false`; (c) upgrade app/identity example to AGP 9,
remove app KGP, flip built-in Kotlin true under Flutter 3.47.1, and smoke an APK;
(d) raise Cockpit's macOS floor and run its desktop release builds. Flutter's
own guidance explicitly separates the temporary 3.44 legacy mode from 3.47's
enabled mode.[flutter-bik]{2} [flutter-app-bik]{2}

### 2. Pin unification

The concrete one-commit quick fix is to change `FLUTTER_VERSION` from `3.41.7`
to `3.44.4` in exactly these four workflows:

1. `.github/workflows/app-release.yml:29-32` — the signed APK builder.
2. `.github/workflows/ci.yml:15-17` — app, app-E2E, and Cockpit validation.
3. `.github/workflows/cockpit-release.yml:28-31` — macOS/Windows/Linux artifacts,
   including the ARM64 git clone that consumes the same variable at lines
   251-258.
4. `.github/workflows/e2e-pairing.yml:14-16` — cross-component pairing E2E.

There is no Flutter pin in `site/`. Its separate reproducibility split is Node
24 in CI (`.github/workflows/ci.yml:316-324`) versus Node 22 in all Docker stages
(`site/Dockerfile:3-4,14-15,28-30`); handle that in the site/Node story rather
than hiding it in the Flutter pin commit.

### 3. KGP migration and plugin tracking matrix

AGP 9 built-in Kotlin means Kotlin source is compiled by AGP without applying
`org.jetbrains.kotlin.android`; Flutter 3.44 temporarily keeps old projects
building with `android.builtInKotlin=false`, and Flutter 3.47 can enable the new
path only when the app and all plugins are compatible.[flutter-bik]{1}
[flutter-bik]{2} The repo is explicitly still opted out of both built-in Kotlin
and the new DSL (`app/android/gradle.properties:8-12`). These are related but
not identical migrations: the Android AGP 10 warning is for
`android.newDsl=false`, not proof that AGP 10 removes the built-in-Kotlin
opt-out.[android-agp9]{2}

**Owned `outpost_pi_identity` change.** Its Android build currently declares a
KGP buildscript dependency, applies `kotlin-android`, and configures old
`kotlinOptions` (`app/packages/outpost_pi_identity/android/build.gradle.kts:4-15,24-41`).
The concrete plugin migration is:

- remove `id("kotlin-android")` and the `android.kotlinOptions` block;
- add top-level `kotlin { compilerOptions { jvmTarget = JvmTarget.JVM_17 } }`;
- retain a KGP classpath/conditional fallback only if supporting consumers below
  AGP 9, following the official compatibility branch; otherwise use the simpler
  Flutter-3.44-minimum form;
- raise the package minimum from Flutter 3.41/Dart 3.11
  (`app/packages/outpost_pi_identity/pubspec.yaml:8-10`) to Flutter 3.44/Dart
  3.12 and record the migration in its changelog; and
- migrate its example app too: it independently applies KGP and old
  `kotlinOptions`
  (`app/packages/outpost_pi_identity/example/android/app/build.gradle.kts:1-20`)
  and still declares AGP 8.11.1/KGP 2.2.20
  (`app/packages/outpost_pi_identity/example/android/settings.gradle.kts:20-24`).

Those steps follow Flutter's plugin guidance rather than merely deleting the
classpath.[flutter-plugin-bik]{1} [flutter-plugin-bik]{2}
[flutter-plugin-bik]{3} Validate both the temporary false path on 3.44.4 and the
AGP-9/true path on 3.47.1.[flutter-plugin-bik]{4}

| Plugin | Locked version / repo evidence | Upstream state on 2026-08-27 | Routing |
|---|---|---|---|
| `outpost_pi_identity` (ours) | 0.2.0 (`app/pubspec.lock:626-632`) | Direct KGP; migrate locally now | bounded owned migration |
| `app_settings` | 5.2.0 (`app/pubspec.lock:4-11`) | 9.0.0 latest; compatible since 8.0.3[pub-app-settings]{1} | major-package migration |
| `flutter_image_compress_common` | 1.1.1 (`app/pubspec.lock:198-213`) | already migrated/current[pub-image-compress]{1} | no blocker; verify |
| `image_picker_android` | 0.8.13+17 (`app/pubspec.lock:421-428`) | migration in +18; +19 latest[pub-image-picker]{1} | compatible lock refresh |
| `mobile_scanner` | 7.4.0 (`app/pubspec.lock:594-601`) | latest conditionally supports built-in Kotlin[pub-mobile-scanner]{1} | no blocker; APK/device smoke |
| `package_info_plus` | 9.0.1 (`app/pubspec.lock:641-648`) | support in 10.2.0; 10.2.1 latest[pub-package-info]{1} | major-package migration |
| `share_plus` | 10.1.4 (`app/pubspec.lock:785-792`) | support in 13.2.0; 13.3.0 latest[pub-share]{1} | major-package migration |
| `speech_to_text` | 7.5.0-beta.1 (`app/pubspec.lock`) | latest stable remains unmigrated, but upstream beta removes KGP[pub-speech]{2} | resolved by exact upstream prerelease pin |
| `url_launcher_android` | 6.3.30 (`app/pubspec.lock:902-917`) | migration in 6.3.31; 6.3.32 latest[pub-url-launcher]{1} | compatible lock refresh |

{inferred: aggregate} Across the matrix, two third-party plugins were already
compatible, two cleared by transitive patch refresh, three required deliberate
major upgrades, and `speech_to_text` cleared through its exact migrated upstream
prerelease. The third-party KGP chain now has a verified resolution; the app
itself remains deliberately unflipped for the next AGP-9 story.

### 4. Dependency freshness

#### App / pub

Live command:

```text
cd app && ../.tools/flutter/bin/flutter pub outdated --no-dev-dependencies
```

reported **17 locked packages with compatible upgrades** and **12 dependencies
constrained below a resolvable version**, not the motivating estimate of 40.
The constrained direct dependencies are:

| Direct package | Locked → resolvable/latest | Assessment |
|---|---:|---|
| `app_settings` | 5.2.0 → 9.0.0 | KGP-clearing major migration |
| `flutter_secure_storage` | 9.2.4 → 11.0.0 | separate storage migration/smoke |
| `go_router` | 17.5.0 → 18.0.0 | routing regression project |
| `package_info_plus` | 9.0.1 → 10.2.1 | KGP-clearing major migration |
| `share_plus` | 10.1.4 → 13.3.0 | KGP-clearing major migration |
| `gpt_markdown` | 1.1.8 → 1.2.1 | compatible upgrade |
| `lucide_icons_flutter` | 3.1.15 → 3.1.17 | compatible upgrade |

The declared constraints are visible in `app/pubspec.yaml:34-45,62-94`; the
lockfile confirms, for example, resolved `app_settings` 5.2.0,
`package_info_plus` 9.0.1, and `share_plus` 10.1.4
(`app/pubspec.lock:4-11,641-648,785-792`). Run compatible lock refreshes
separately from majors so failures remain attributable.

#### Relay / Rust

- `cargo audit` exited successfully after scanning 248 locked dependencies: no
  RustSec vulnerability was reported. The repo also runs scheduled `cargo
  audit` for relay and `rp-s3` (`.github/workflows/deps-audit.yml:44-60`).
- `cargo update --dry-run` proposed 75 Rust-1.94-compatible lock updates, so a
  lock refresh is worthwhile even though declared direct versions are recent.
- Four declared major lines are behind current stable metadata: axum 0.7→0.8,
  ed25519-dalek 2→3, rand 0.8→0.10, and dev-only reqwest 0.12→0.13
  (`relay/Cargo.toml:14-35`).[crates-current]{1} Treat those as API migrations,
  not a lock refresh.
- The project says Rust 1.94+ (`relay/CLAUDE.md:15-20`) and this host runs rustc
  1.94.0, but `Cargo.toml` has no `rust-version` alongside edition 2024
  (`relay/Cargo.toml:1-5`), no `rust-toolchain(.toml)` exists, and CI follows
  floating `stable` (`.github/workflows/ci.yml:167-181`). Add a checked-in 1.94
  minimum/pin decision so local and CI evidence mean the same thing.

#### Pi extension / Node / Pi SDK

- The extension declares Node `>=20` and pins Pi SDK 0.80.6 exactly
  (`pi-extension/package.json:61-63,80-91`), but Pi 0.80.6 itself already
  requires Node `>=22.19.0`.[npm-pi]{1} This is a present contract bug: raise the
  extension engine floor at least to `>=22.19.0`. CI's Node 24 already satisfies
  it (`.github/workflows/ci.yml:141-159`).
- `pnpm outdated` found only small TypeBox/Vite/Vitest/type-definition updates
  plus Pi SDK 0.80.6→0.84.3. The SDK is not a blind pin bump: upstream removed
  `AuthStorage` after this pin and changed registry/event contracts.[npm-pi]{2}
  [npm-pi]{3} Outpost-Pi directly imports `AuthStorage` and assumes synchronous
  `refresh()` (`pi-extension/src/actions/registry.ts:18-30`,
  `pi-extension/src/actions/handlers.ts:104-110`). Its streaming hook already
  consumes `assistantMessageEvent` deltas
  (`pi-extension/src/index.ts:1441-1447`), which reduces—but does not eliminate—
  0.84 migration work. Route this as a bounded SDK adapter migration with full
  extension lifecycle tests.

#### Site / Node / Next

- Site pins Next 16.3.0, React 19.2.8, and matching ESLint config
  (`site/package.json:14-29`). Registry latest is Next 16.3.3, still major 16,
  so there is no Next-major migration; take the patch with lint/build/browser
  checks.[npm-next]{1}
- CI uses Node 24 while Docker builds and runs on Node 22
  (`.github/workflows/ci.yml:316-324`, `site/Dockerfile:3-4,14-15,28-30`). Both
  satisfy Next, but Node 24 is the current LTS line while 22 is already in
  maintenance.[node-schedule]{1} Prefer Node 24 across CI/Docker and add a site
  `engines.node` floor (at least Next's `>=20.9.0`; preferably the chosen Node
  24 policy). Do not move to Node 26 before its LTS date.[node-schedule]{1}

## Prioritized migration plan

### Quick wins

1. **Unify Flutter at 3.44.4** in the four workflow pins. This is the one-commit
   reproducibility repair and does not claim the 3.47 migration is complete.
2. **Refresh compatible app locks**: take `image_picker_android` +19,
   `url_launcher_android` 6.3.32, and compatible direct/transitive patches;
   analyze, test, APK-smoke, and retain the Pixel Fold IME regression.
3. **Correct the Node contract**: raise `pi-extension`'s engine floor to
   `>=22.19.0`; align site CI/Docker on Node 24 and take Next 16.3.3.
4. **Refresh relay's compatible lock set** under Rust 1.94 and rerun fmt,
   clippy, tests, build, and `cargo audit`.

### Bounded migrations

1. Migrate `outpost_pi_identity` plus its example to the Flutter-3.44-compatible
   built-in-Kotlin shape.
2. Upgrade `app_settings`, `package_info_plus`, and `share_plus` to their first
   migrated/current major lines, each with feature-specific regression checks.
3. Resolve `speech_to_text` by a minimal maintained fork, replacement, or an
   upstream release; this decision gates built-in Kotlin.
4. Migrate the app itself to AGP 9/built-in Kotlin, then upgrade directly from
   Flutter 3.44.4 to 3.47.1. Raise Cockpit macOS deployment/appcast floors to 12
   in the same Flutter target story and execute platform release smokes.
5. Upgrade Pi SDK 0.80.6→0.84.3 through the registry adapter and lifecycle seam;
   do not mix it with routine pnpm patch refreshes.
6. Evaluate relay's four Rust major migrations independently of the compatible
   lock refresh.

### Tracked upstream / evidence gates

- `speech_to_text` 7.5.0-beta.1 is the first upstream built-in-Kotlin release;
  retain its exact prerelease pin until stable 7.5+ carries the migration.
  [pub-speech]{2}
- Flutter 3.47 has no attested Android stale-IME/inset fix; keep the watchdog and
  require physical Pixel Fold UAT before considering removal.
- The Flutter breaking-change index lists `describeEnum` removal under 3.47,
  while its detail page still says the landed/stable version is TBD.
  [flutter-breaking-index]{2} [flutter-describe-enum]{1} This source
  contradiction is immaterial to current code because the targeted scan found
  no use, but the migration story should let analyzer/compiler evidence settle
  it rather than repeating either page as definitive.

## Disconfirming analysis

1. **Package-debt count:** re-running the requested no-dev pub audit disproved
   the seed's “40 constrained” estimate for current HEAD: the command reports 12
   constrained dependencies and 17 compatible locked updates. The plan uses the
   live result.
2. **AGP 10 deadline:** Android's documented AGP 10 removal warning is attached
   to the old-DSL opt-out, while Flutter separately plans/removes support for
   plugins applying KGP.[android-agp9]{2} Treating these as one flag would produce
   the wrong migration test; both must be verified separately.
3. **IME hypothesis:** searches across both 3.44 and 3.47 release notes found
   keyboard fixes, but none match Android/Pixel-Fold stale WindowManager insets.
   The result is “not evidenced,” not “3.47 does not fix it.” Device UAT remains
   the discriminator.
4. **“Latest” does not mean “quick”:** current Pi SDK and pub major candidates
   carry documented contract changes; splitting patch refreshes from migrations
   preserves attribution and rollback.

## Proposed child-story decomposition (do not spawn in this engagement)

| Proposed id | Scope | `depends_on` |
|---|---|---|
| `story-unify-flutter-3-44-4-pins` | Change the four workflow pins; verify action configuration | `[]` |
| `story-refresh-app-compatible-dependencies` | Compatible pub/lock refresh including image-picker/url-launcher KGP patches | `[story-unify-flutter-3-44-4-pins]` |
| `story-migrate-outpost-pi-identity-built-in-kotlin` | Owned plugin + example + dual-mode build tests | `[story-unify-flutter-3-44-4-pins]` |
| `story-upgrade-app-settings-built-in-kotlin` | `app_settings` major migration and settings-link regression | `[story-unify-flutter-3-44-4-pins]` |
| `story-upgrade-plus-plugins-built-in-kotlin` | `package_info_plus` + `share_plus` migrated majors and version/share tests | `[story-unify-flutter-3-44-4-pins]` |
| `story-resolve-speech-to-text-built-in-kotlin` | Upstream release vs minimal fork/replacement decision and implementation | `[story-unify-flutter-3-44-4-pins]` |
| `story-migrate-app-agp9-built-in-kotlin` | App KGP/new-DSL migration; flip built-in Kotlin true and APK smoke | `[story-refresh-app-compatible-dependencies, story-migrate-outpost-pi-identity-built-in-kotlin, story-upgrade-app-settings-built-in-kotlin, story-upgrade-plus-plugins-built-in-kotlin, story-resolve-speech-to-text-built-in-kotlin]` |
| `story-upgrade-flutter-3-47-1-platform-floors` | Flutter/Dart pin, Cockpit macOS 12 floor/appcast, app + desktop verification, Pixel Fold UAT | `[story-migrate-app-agp9-built-in-kotlin]` |
| `story-upgrade-pi-sdk-and-node-floor` | Node engine correction, Pi 0.84.3 adapter migration, full extension suite | `[]` |
| `story-refresh-relay-rust-toolchain-dependencies` | Rust 1.94 pin/minimum, compatible lock refresh, audit; record majors separately if needed | `[]` |
| `story-align-site-node24-next-patch` | Node 24 CI/Docker/engine alignment and Next 16.3.3 patch | `[]` |

## Verification outcome and stage

- Citation/grounding spot-check covered web-current versions, local version pins,
  KGP build files, platform floors, and load-bearing dependency claims.
- Standard-rigor adversarial re-read produced and corrected three material
  issues before landing: the stale “40” count, the KGP/new-DSL AGP-10
  conflation, and overclaiming an IME non-fix from absence in release notes.
- No unresolved contradiction blocks the recommendations; `describeEnum` is
  recorded above as a non-blocking source contradiction.
- Research findings are complete. Per the operator's explicit contract, this
  item **stays `stage: implementing`** so the orchestrator can review the proposal
  and spawn stories.

## Decomposition executed (2026-08-27)

10 stories spawned (pins story pre-completed at dormancy setup). Scope
revision recorded: 3.47 upgrade is app-only per cockpit dormancy
(freeze-with-guard, operator 2026-08-27). Quick wins dispatched same-day.

## KGP dependency-chain outcome (2026-08-28)

The four dependency stories are done. A Flutter 3.44.4 debug APK builds with no
**plugin** KGP warning; the one remaining warning names the app project itself,
which is intentionally reserved for `story-migrate-app-agp9-built-in-kotlin`.
Three hosted plugins were already dual-mode compatible but triggered Flutter
3.44's lexical scanner on their conditional AGP-8 fallback. Checked-in build
overlays preserve those conditions while using a scanner-safe `pluginManager`
spelling; `app/android/plugin-builds/README.md` owns the short-lived carry and
removal condition.
