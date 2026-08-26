---
id: gate-cruft-v050-dead-code-sweep
created: 2026-08-15
updated: 2026-08-26
tags: [pi-extension, app, cleanup]
status: folded
folded_into: feature-cruft-consolidated-cleanup (groom 2026-08-26)
---

# Post-v0.5.0 dead-code sweep (2 verified instances)

Post-hoc v0.5.0 cruft-gate findings. Confidence: High (tool-verified).

1. **Unused hot-reload path helpers** — `pi-extension/src/index.ts:2695`
   (`_hotReloadEnabledPath`) and `:2707` (`_runtimeIdentityPath`):
   `tsc --noUnusedLocals --noUnusedParameters --noEmit` flags both;
   repo-wide search finds only their declarations. Remove or route the
   corresponding path construction through them.
2. **No-op conditional in EPK normalization** —
   `app/lib/data/transport/epk_encoding.dart:30`: `if (out != b64) {}`
   empty body, no side effects, function returns `out` immediately after.
   Remove the conditional, preserve conversion/return behavior.
