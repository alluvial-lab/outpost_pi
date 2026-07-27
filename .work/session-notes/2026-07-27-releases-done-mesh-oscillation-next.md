# SESSION NOTE — 2026-07-27 — releases complete; mesh-oscillation bug is next (RESUME HERE)

## TL;DR

Shipped the full v0.3.0 release family, then spent the day on a phone
incident chain that turned out to be ONE app-side bug in three costumes
(plus a separate pairing race, now fixed). **Next session: fix
`story-mesh-reconciliation-deletes-pairing-channel`** — the mesh
reconciliation deletes device-local channel keys on blob authority;
phone pairing is currently re-paired-but-fragile until it lands.

## Releases (all shipped, tags local — PUSH PENDING)

- `v0.3.0` on `fedf37f` · `app-v0.3.0` on `46a888c` · `cockpit-v0.3.0` on
  `530cf7b` (UAT pass-with-note: operator doesn't use cockpit).
- Skipped: extension-0.3.0 (all cross-component, shipped via v0.3.0),
  relay-0.3.0 (empty: 4 stamped husks + 1 v0.1.0-bound).
- **Push:** `git push origin main v0.3.0 app-v0.3.0 cockpit-v0.3.0`
- Backlog groomed same day: 1 deleted, 1 superseded, 3 folded into
  backlog-cruft-removal-batch. 65 valid backlog items.

## Infra deployed (durable)

- **Tailscale on codebox**: docker container `tailscale`
  (`--entrypoint tailscaled` — stock boot script crash-loops), node
  `100.106.7.70`, advertises `192.168.50.0/24` (approved). Relay answers
  on LAN + tailnet IPs. Documented in AGENTS.md.
- Phone: Tailscale split-tunnel include-mode (Outpost-Pi + Termux),
  always-on + battery-unrestricted. WireGuard must stay fully off (single
  VPN slot; they fight). App relay URL stays `http://192.168.50.110:3300`
  (works direct at home AND via subnet route remotely).

## Incident chain (2026-07-26→27) — what each breakage actually was

1. **~04:54 steering**: phone dual-homed ("mobile data always active" +
   smart switch) flipped app traffic to cellular. Pure infra.
2. **15:37 "relay offline, nothing here"**: attributed to owner transition
   at the time — WRONG. It was the mesh-oscillation bug (below) deleting
   the pairing's channel keys. Fingerprint key existing ≠ transition
   fired (it initializes on first boot regardless).
3. **17:41 + 00:47 "Format error" pairing**: REAL v0.3.0 race — backlog
   frames racing `pair_ok` crashed `performPairing`'s single-frame read
   (`FormatException: Unexpected extension byte`). **FIXED** in
   `story-pairing-flow-single-frame-read-race` (reply-matching read loop +
   closed-transport empty-frame guard; 849/849 suite; shipped in the
   0.3.0+2 debug APK).
4. **02:47 dead after hard close**: instrumented (`retryConnect`
   lifecycleFailure events now record exception runtimeType — keep this,
   it's generally useful) → `PeerChannelError` = channel-less record
   again. Root-caused to mesh reconciliation.

## THE bug for next session

`story-mesh-reconciliation-deletes-pairing-channel` (drafting, highest
priority). Hypothesis: pulled owner-signed blob treated as authoritative
for FULL membership while each publisher only publishes its own pairings
→ LWW oscillation → each side's reconciliation `deletePeerSilent`s the
other's latest member incl. channel keys (unrecoverable without re-pair).
Signature: 00:47 "Paired" immediately followed by "Revoked by Owner
o4bghjDo…". Start with the failing test in the story body
(extension-authored blob missing local pi epk → pull → local
channel-bearing record must survive; today it doesn't).

## Phone state right now

- Re-paired at ~01:07 (works), but every cold-start pull risks the wipe
  until the fix lands. Debug APK on phone has the pairing-race fix +
  `retryConnect` instrumentation (both committed).
- Evidence preserved: debug/ 90b/914/935/938/94f/963/965 captures;
  extension audit ~/.pi/remote/owner-channel-audit.jsonl; relay log in
  container volume.

## Board

- Active: reconnect epic arc (implementing, phone-repro gated) +
  `story-mesh-reconciliation-deletes-pairing-channel` (drafting, DO THIS
  FIRST) + `story-mobile-transcript-reorder-after-backlog-flush`
  (drafting, same arc; append-by-arrival hypothesis) + 5 drafting.
- Backlog: 65 valid incl. `story-identity-boot-restore-race` (real but
  NOT what bit us this week — mesh bug was misattributed to it),
  `app-relay-url-network-failover`, `app-hydration-truncated-flag-not-surfaced`.
