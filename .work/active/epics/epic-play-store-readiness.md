---
id: epic-play-store-readiness
kind: epic
stage: drafting
tags: [app, distribution]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-25
updated: 2026-08-25
---

# Play Store readiness (parked — distribution decision pending)

Operator parked 2026-08-25 after assessment; triggered again when
distribution-to-others becomes real. Shares the keystore decision with the
per-device-sideload feature (same key serves both).

## Assessment (2026-08-25, from the v0.8.0-era codebase)

**Code is close; work is around the app, not in it.**

### One-time infrastructure (small)
- Play developer account ($25). NOTE post-Nov-2023 personal accounts
  require a closed test with 20 testers for 14 continuous days before
  production; org account (D-U-N-S + entity verification) skips that.
  Account strategy is the one thing agents cannot build away.
- Play App Signing: real keystore + upload key (kills the 0.1.0
  dropped-release-signing debt).
- AAB builds (`flutter build appbundle --release`) — Play requires AAB for
  new apps; per-device split happens at Play's side automatically.
- Privacy policy URL (site/ subproject hosts it), store listing (golden
  harness can generate screenshots), data-safety form (no collection;
  sealed traffic to user's own relay).

### Policy compliance (the real work)
- Generative-AI policy: in-app content reporting/flagging required for
  AI-chat features — largest code item (report affordance + routing).
- Review accessibility: app requires the user's own Pi — needs demo mode
  or a review-notes video; the sync-gate hard wall is a reviewer risk.
- 16KB page-size alignment for Android 15+ targets (verify libflutter).
- Export-control checkbox, IARC, camera/mic declarations — forms.

### Synergy with what exists
- Play internal-testing track ≈ our rc-draft UAT loop (sideloading dies).
- Play vitals = free crash telemetry. Staged rollouts match our version
  discipline.

### Sizing
~two features: "Play mechanics" (signing+AAB+listing, ~week of agent work)
+ "AI policy + review path" (design-bearing, needs product calls).

## Decomposition sketch (when un-parked)
F1 signing+AAB pipeline; F2 AI-reporting affordance; F3 review/demo mode +
listing assets; F4 policy forms + account strategy (operator decisions).
