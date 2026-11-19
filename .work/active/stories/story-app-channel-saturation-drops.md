---
id: story-app-channel-saturation-drops
kind: story
stage: done
tags: [relay, app, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-11-15
updated: 2026-11-15
---

# App↔relay channel drops: outbound-mailbox saturation shedding + replay re-feed spiral

## Brief

The Android app's relay channels drop repeatedly (`closeCode 1002 /
dartProtocolError`, one `1006/streamDone`), presenting as protocol failures.
Two capture-triage rounds (2026-10-18, 2026-11-15) plus relay-log correlation
establish the real mechanism: **the relay force-closes the phone's peer when
its bounded outbound mailbox saturates** — the phone's link cannot drain
multi-hundred-KB frames fast enough — and the app-side `1002` is merely how a
torn-down stream surfaces in Dart's WS layer. On reconnect, room-history
replay re-feeds the same giant frames, re-saturating the mailbox: a
reconnect-replay death spiral. A second, separate aggravator: the phone's
WiFi path (192.168.40.23) fails relay auth chronically (`phase="auth"`),
succeeding only via tailscale.

## Triage record (evidence chain; key numbers inlined — capture files are retention-managed and transient)

**Captures** (NDJSON app event logs, `debug/`):
- `app-capture-2026-10-18T00-28-17-966Z-c8142fb30d56.bin` — 7,019 events,
  5 channel losses (4 root-room, 1 nextup), 220,631-byte replay envelopes
  observed pre-drop, hello→close(~3s) reconnect aborts, retry ladder
  1/2/5/10/30s with 15s connect timeouts, replay-dedup bursts 400–1800/min.
- `app-capture-2026-11-15T19-11-42-335Z-58b893818046.bin` — 7,055 events
  spanning Nov 13–15, 10 losses (9 root-room, 1 `83MK6OkhBrcQ`), new
  `WebSocketChannelException` retry variant, one `1006/streamDone`.

**Relay logs (decisive):**
- `relay initiated peer socket close peer=qQLDCu8= room=main
  close_reason="relay_outbound_mailbox_saturated"` at 2026-11-15T19:07:00.411
  and 19:11:03.124 — sub-second-correlated with the app's drops at
  19:07:00.695 (1006) and 19:11:03.227 (1002, outpost room).
- **102 saturated closes all-time, every single one peer `qQLDCu8=`** (the
  phone: tailscale `100.121.111.25` / WiFi `192.168.40.23`, same device).
  Worst storms Oct 4–5 (21 closes) — exactly the days of app-capture upload
  sessions. Sporadic 1–2/day since on active days.
- Room `main` is the phone's solo room (sole member since 2026-09-08).
- Outbound frame sizes to that room reach **1,052,637 bytes** (all-time max;
  599,213 bytes measured 2 min before the 19:07 saturation). Mailbox holds
  18–251 frames at shed time ≈ megabytes queued.
- Auth-phase failures from `192.168.40.23`: 166 on Oct 5, 55–68/day on
  recent active days; phone then succeeds via tailscale.

**Identity map (from relay auth logs):** `qQLDCu8=` = phone app (both
network paths), room `main` member. `YKC6UmHU=` = per-room bridge identity
fanning into per-cwd rooms (Oct 9 evidence). The capture events' `peerTail`
values refer to these app-side identities.

## Mechanism

1. Large payloads transit the phone's room (replay envelopes and/or capture
   upload/download traffic; exact producer of the 1MB frames — see open
   questions).
2. Phone link drains slower than the relay fills → bounded per-peer outbound
   mailbox fills → relay sheds the connection (recorded
   `relay_outbound_mailbox_saturated`; delivered to the app as a stream
   error, not a distinguishable close).
3. App classifies the torn stream as `1002/dartProtocolError` → retry
   ladder → reconnect → relay replays room history (same giant frames) →
   immediate re-saturation → spiral until the link happens to drain a full
   replay.
4. Independently, WiFi-path auth failures force tailscale-only operation on
   the phone whenever it is on the 192.168.40.x LAN.

The 2026-10-18 triage's downlink/handshake hypotheses described the drain
side; the kill side is the relay's saturation close. Both prior hypotheses
are superseded by this mechanism.

## Design (chosen 2026-11-15, evidence-constrained)

Source-verified facts shaping the design:
- Relay mailbox: `resource_limits.rs` `OUTBOUND_QUEUE_CAPACITY=16`, drop-newest
  + disconnect-signal on saturation (`peers/connections.rs` `deliver()`).
  Bounded memory + forced hydration for authoritative frames is the documented
  contract — preserved as-is; no queue/capacity/backpressure redesign.
- Saturation close currently tears the socket down as a stream error
  (`handlers/peer.rs` `CLOSE_OUTBOUND_MAILBOX_SATURATED` → disconnect signal),
  which is why the app sees 1002/1006 with no distinguishable reason.
- Producer of large frames: app↔Pi owner-channel envelopes through the
  phone's solo relay room `main` (opaque forward, ct cap 4MiB). Transcript
  streaming/replay is the fill source. No replay redesign in this story.

Scope: FD-1 (relay graceful 1013 + reason instead of stream-error teardown)
+ FD-3 (app classification/observability for that close) + PROTOCOL.md doc.
FD-2 (replay bounding) and FD-4 (WiFi auth) stay open follow-ups; replay
redesign is NOT included here. Mixed-version safe: 1013 is
reconnect-recoverable; an old app retries as today.

## Fix directions (design input, not chosen)

- **FD-1 — Relay close semantics:** make backpressure shedding a clean,
  distinguishable close (e.g. WS close code 1013 "try again later" with the
  saturation reason) instead of a stream error the app must misclassify.
  Consider whether shedding should first apply flow control (pause replay
  feed) rather than close.
- **FD-2 — Replay re-feed bounding:** room-history replay on join must not
  re-queue unbounded giant frames: chunk/paginate, cap single-frame size at
  the producer, and/or resume from a cursor (dedup event-ids already exist
  app-side). This kills the spiral.
- **FD-3 — App-side failure classification:** label transport/backpressure
  closes distinctly from protocol errors (the `1002/dartProtocolError`
  mislabel made two triage rounds harder than necessary).
- **FD-4 — WiFi auth failures:** diagnose the `phase="auth"` failure mode
   from 192.168.40.23 (signature/nonce/clock-skew class) — separate axis,
  same symptom family.

## Open questions (for design)

- What exactly produces the 0.2–1MB envelopes into the phone-solo room
  `main` (capture-delivery echo? replay of the phone's own uploads? a
  bridge writing large payloads)? Needs relay-side frame provenance.
- Whether the app's other-room channels die as collateral of the `main`
  channel shed (shared fate at the app's channel supervisor) or of a
  network-level reset — the sub-second correlation suggests shared fate
  worth confirming in app source.
- Mailbox bound definition (bytes vs frames) and whether saturation
  accounting differs per room channel — relay source check.

## Review (2026-11-19, cross-model, bounded)

Outside reviewer: `openai-codex/gpt-6.1-sol` (high). Verdict:
APPROVED-WITH-NITS (no blockers). Nits resolved: PROTOCOL.md now states the
1013 close is a bounded best-effort attempt (a blocked/dead connection still
surfaces as ordinary transport loss); the integration test's 20ms sleep was
replaced with a deterministic `rooms_check` snapshot barrier (subscribe_rooms
emits nothing itself), capacity+1 fill re-verified. Confirmed by the reviewer:
the 1s close bound stalls only the dying connection; the app classifies a
received 1013 on the normal streamDone path (streamError metadata check is
harmless defense); mixed-version directions safe; no payload logging; tests
exercise real boundaries (actual registry saturation observed over a real WS).
Shared-fate question resolved from source during implementation: the app runs
ONE active channel (`ConnectionManager`, `connection_manager.dart:2061-2088`),
so room targets share transport teardown by construction — the cross-room
losses in the captures are the same socket dying, not collateral.

## Implementation notes (2026-11-19)

- Execution capability: delegated workhorse lane
  (`kimi-coding/k3.1-pro-highspeed`, high) with orchestrator review +
  independent re-verification. Ledger row: admin/highspeed-workhorse-trial.md.
- Files: `relay/src/handlers/peer.rs` (graceful 1013 + reason on saturation,
  1s bounded write, existing drop-newest/16-frame contract preserved),
  `relay/src/metrics.rs` (read accessor), `relay/tests/{common/mod.rs,
  integration.rs}` (fixture + real-boundary saturation test), 
  `app/lib/data/transport/ws_transport.dart` (exact 1013+reason →
  serverCloseFrame + transportBackpressure; other reasons still "present"),
  `app/test/data/transport/{ws_transport_close_diagnostics_test.dart,
  connection_manager_test.dart}`, `PROTOCOL.md` (close + compat matrix).
- Orchestrator re-verification: relay fmt/clippy/test (240 incl. integration),
  flutter analyze + full app suite 1079 passed.
- Out of scope (unchanged): reconnect/backoff behavior, replay re-feed
  bounding (FD-2 follow-up), WiFi auth failures (FD-4 follow-up).

## Provenance

Two operator-delivered Android debug captures (2026-10-18, 2026-11-15) with
in-conversation triage; relay docker-log forensics 2026-11-15; operator
direction "park triage yes" same day. October capture retained in `debug/`
as live evidence until superseded by the fix landing.
