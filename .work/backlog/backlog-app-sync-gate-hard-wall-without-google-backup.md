---
id: backlog-app-sync-gate-hard-wall-without-google-backup
created: 2026-08-23
updated: 2026-08-23
tags: [app, design-question]
---

# First-launch sync gate hard-walls devices without Google Backup — no local-only path

Found during the 2026-08-23 fold usability pass (emulator reproduction):
`packages/outpost_pi_identity/.../BlockStoreStore.kt` `isSyncAvailable()`
requires Play services + secure lockscreen + a Block Store `retrieveBytes`
probe; the probe fails on any device without Google Backup configured
(no account, de-Googled ROM, pre-provisioned device, every emulator), and
`app_router.dart`'s sticky `/sync-required` redirect then blocks ALL further
onboarding. Design intent (Plan 23: prevent silent owner-identity divergence
on multi-device sync) is sound, but there is no operator-visible escape
hatch — e.g. an explicit "continue without cloud key sync (this device
re-pairs on loss)" acknowledgement. Also note the testing gap: the e2e live
harness bypasses the gate via restored-pair widget pumping, so the
production onboarding path past this gate is never exercised on CI. Decide
product-side: local-only escape hatch vs documented hard requirement; if
the latter, the copy should say "cannot proceed" rather than implying the
user merely misconfigured something.
