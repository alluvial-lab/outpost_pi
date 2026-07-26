# 2026-07-26 — Tailscale deployment + phone routing incident (RESUME HERE)

## What shipped

- **Tailscale on codebox**: docker container `tailscale` (tailscale/tailscale,
  `--network host`, `--cap-add NET_ADMIN`, `/dev/net/tun`, state volume
  `tailscale-state`, `--entrypoint tailscaled`, restart unless-stopped).
  Node `codebox` = `100.106.7.70`. NOT the stock image entrypoint — its boot
  script kills `tailscale up` at 60s and crash-loops the nodekey.
- **Subnet route**: codebox advertises `192.168.50.0/24` (host ip_forward
  already =1; container /proc is RO but the value is correct). Operator
  approved the route in the admin console. Relay answers on both
  `192.168.50.110:3300` and `100.106.7.70:3300` (curl 400 = alive).
- **Phone**: Tailscale app, split tunneling INCLUDE mode with Termux +
  Outpost-Pi on the list. App relay URL UNCHANGED: `http://192.168.50.110:3300`
  (works at home direct-LAN, remote via subnet route). WG and TS fight over
  the single Android VPN slot — one must be fully off.

## Incident arc (all infra, zero product defects)

Phone dual-homed (rmnet1 UP + default route + global IPv6 despite "mobile
data off" — suspect Dev-Options "mobile data always active" + smart switch).
~04:54 steering flipped the app's traffic to cellular → relay-unreachable
incident; relay saw zero attempts (auth-level logging only). App behaved
correctly throughout (backoff, no corruption). Parked:
`app-relay-url-network-failover` (unreachable-vs-refused diagnostics +
relay-address failover).

## Where it stands (2026-07-26 ~21:30Z)

- WG full-tunnel: app auths fine via WG (17:58/18:04, source 192.168.11.2).
  Interim remote path — operator can keep using it.
- TS on phone: connects briefly then dies repeatedly (pixel node
  idle/offline). Possible VPN-slot contention with WireGuard always-on.
- With TS Connected: Termux (added to split tunnel) pings BOTH
  100.106.7.70 and 192.168.50.110 OK. Outpost-Pi (also on include list)
  still cannot connect; relay sees zero attempts.

## Open investigation (resume here)

Leading suspect: Android bound the app UID to rmnet1 during the steering
incident; per-UID fwmark rules override VPN include lists.
Definitive tests (operator remote; adb at workstation):
1. Termux+TS: `curl -m 5 -o /dev/null -w "%{http_code}\n" http://192.168.50.110:3300/` (expect 400).
2. Remote try: force-stop app → airplane ON/OFF → TS connected → open app.
3. Workstation: `adb shell "dumpsys package dev.kevoun.outpostpi | grep -m1 userId"` then `adb shell "ip route get 192.168.50.110 uid <uid>"` —
   `dev rmnet1` = smoking gun; `dev tailscale0/wlan0` = look elsewhere.
Also check: Settings → VPN — which app holds "Always-on VPN" (must be
Tailscale, WireGuard off); Battery → Unrestricted for Tailscale.

## Evidence

App debug captures in debug/ (90b/914/935/938 series); relay log
`docker exec outpost-pi-relay tail /data/logs/relay.log.$(date -u +%F)`;
extension audit ~/.pi/remote/owner-channel-audit.jsonl (17:41 pairing-storm
sequence_persist_failed burst, self-resolved; separate ~24-peer
cross-PC cluster at 17:45 worth a later look — other room SF_DCbXsmreE).
