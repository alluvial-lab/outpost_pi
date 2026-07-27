# SESSION NOTE — 2026-07-27 — mesh reconciliation fix landed (cb463cb)

## TL;DR

`story-mesh-reconciliation-deletes-pairing-channel` is **done**. Root cause
was the story's "narrower" hypothesis, not the multi-publisher model: the
extension never publishes (GET-only `MeshClient`); the app's own
reconciliation matched base64-standard blob members against base64url local
record keys by raw string, missed ~3/4 of keys, and `deletePeerSilent`-ed
the channel-bearing record on every cold-start pull → `PeerChannelError`
brick. Fix: canonical-epk matching + blob absence is no longer deletion
authority for channel-bearing records + duplicate-spelling collapse.
Verified: 3 new red→green tests, app suite 852/852, analyze clean, e2e
pairing 16/16 + canaries.

## Commits (local, PUSH PENDING along with v0.3.0 family tags)

- `cb463cb` fix(app): mesh reconciliation no longer bricks channel-bearing pairings
- `3e8a115` fix(e2e): pair-code seam consumed per attempt (harness was
  1 pass / 15 fails since the 07-25 seam-hardening; host runtime wipes the
  seam file per generation, `waitForPairCode` consumes via DELETE
  /pair-code — mirrors the Cockpit consumer contract)

## Next actions

1. **Sideload the fixed app** — phone pairing is still fragile until the
   APK with `cb463cb` is on the device. Re-pair once more after install
   (the current channel record on the phone may already be a channel-less
   standard-spelling husk from the last wipe).
2. **Uncommitted leftover**: `app/lib/data/transport/connection_manager.dart`
   has a dirty hunk from the 07-27 debug session (retryConnect
   `_logLifecycleFailure` on scheduled retry). The 07-27 note said the
   instrumentation was committed — this piece wasn't. Decide: commit or
   drop. It looked intentional and privacy-safe (peer tail + room only).
3. Push: `git push origin main v0.3.0 app-v0.3.0 cockpit-v0.3.0` (from the
   operator's machine).

## Board

- Done: story-mesh-reconciliation-deletes-pairing-channel.
- Next per 07-27 note: `story-mobile-transcript-reorder-after-backlog-flush`
  (drafting) or the reconnect epic arc (implementing, phone-repro gated).
