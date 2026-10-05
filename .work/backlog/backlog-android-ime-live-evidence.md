---
id: backlog-android-ime-live-evidence
created: 2026-10-05
updated: 2026-10-05
tags: [app, docs]
---

# Replace fake IME convergence confidence with production Android evidence

The fake-environment convergence assertion proves only mock mutation; a live Android window-insets seam should own real inset convergence. Folded from two gate-tests findings that define complementary ownership of the same assertion (live seam + fake-assertion removal).

Consolidated 2026-10-05 by operator-confirmed groom merge from: gate-tests-android-ime-recovery-live-seam, gate-tests-remove-fake-ime-convergence-assertion.
Scope-promote via /agile-workflow:scope when wanted.
