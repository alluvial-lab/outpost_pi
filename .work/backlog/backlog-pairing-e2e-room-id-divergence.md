---
id: backlog-pairing-e2e-room-id-divergence
created: 2026-08-12
updated: 2026-08-12
tags: [app, pi-extension, bug]
---

# pairing-e2e room-ID divergence (status room ≠ QR room) — CI RED regression

## Status
**CI is red on this.** pairing-e2e fails on every run since the v0.4.0-era commit push (56c5701 onward); was green-capable at 0023ccd (Aug 7 dependabot push succeeded). Top-priority fix.

## Origin
v0.4.0 push (2026-08-12): pairing-e2e CI failed. First diagnosed (wrongly) as a parallel-test flake; **corrected after reading e2e/run-pairing.sh — the suite already runs `flutter test --concurrency=1` (serial), so it is NOT parallel contamination.**

## Real diagnosis
The pi-host publishes **one room ID in its status endpoint but a different one in its published pair-code/QR** (deterministic: status `wc3B14rFnkrH` vs QR `KzJ3MohnQOvq`, swapped in some tests). Within-host divergence across two channels, not test parallelism. Symptom is non-deterministic in *which* tests trip (4 vs 7 across runs) + a 10s `TimeoutException` in session_hydration → timing-dependent.

cross_room_pairing_e2e_test asserts `expect(pairCode.qr.roomId, status.roomId)` after `host.restartForIsolation()` — the QR's room should equal the host status room; they diverge.

## Reproduced locally
`bash e2e/run-pairing.sh` on the VM → `+12 -4` (same room-swap + timeout). So it is a real bug, not CI-env-specific.

## Regression source
The done-work commits that were local Jul 27 → pushed Aug 12 (56c5701 onward). Suspects (pairing/room-adjacent):
- canonical-transcript-ordering (app sync_service + projection, extension broadcast)
- pair_request_flow typed decoder (app)
- to_room sender-side room targeting (extension) / room-keying by (cwd, name)
- relay room-derivation (status path vs QR path)

## Work
Root-cause where the extension/pi-host's **status roomId** diverges from its **QR/pair-code roomId** after isolation/restart (`qr.ts:113 params.set("rm", roomId)` is the QR sink; find the status-side counterpart + the shared derivation). Fix so both report the host's actual current room. Verify: `bash e2e/run-pairing.sh` green locally, then CI green.
