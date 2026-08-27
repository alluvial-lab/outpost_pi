---
id: feature-stack-currency-review
kind: feature
stage: drafting
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
