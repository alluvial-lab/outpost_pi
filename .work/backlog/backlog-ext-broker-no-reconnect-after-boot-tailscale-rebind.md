---
id: backlog-ext-broker-no-reconnect-after-boot-tailscale-rebind
created: 2026-08-23
updated: 2026-08-23
tags: [pi-extension, bug]
---

# Broker holds no relay socket after VM reboot + tailscale link rebind

Operator report (2026-08-23): after a VM reboot the phone saw no sessions.
Diagnosis on the VM (03:2x UTC):

- Relay container auto-started at boot (restart=unless-stopped), healthy the
  whole time; `GET /health` OK via both localhost and the tailscale path.
- All pi agents (restart wrapper) started ~2 min after boot; the extension
  broker in EVERY agent had **zero established sockets** to
  `http://<tailnet-ip>:3300` (the configured relay URL in
  `~/.pi/remote/config.json`) hours later — only the model-API connection
  remained per process.
- `~/.pi/remote/owner-channel-audit.jsonl` last writes at 00:37 UTC:
  `sequence_persist_failed` ×3 (three peers) — extension-side persistence
  failure, ~2h before the phone symptom.
- `docker logs tailscale` shows `Rebind; ... major link change` at 01:10:32
  UTC — a late tunnel rebind that would have torn down any WebSocket still
  standing. No reconnect happened afterwards, while the path was healthy.

## Work

The extension broker's reconnect loop did not survive (or never re-established
after) the transport loss; it must reconnect indefinitely like the app does.
Reproduce with a mid-session tailscale-style rebind (or toxiproxy hard-cut on
the extension→relay leg), find why the loop exited (audit log suggests the
sequence_persist_failed path may be fatal rather than retried), and add the
reconnect-always regression test to the pi-extension suite.

Remediation at the time: full agent restart via `scripts/refresh-dist.sh`
(fresh brokers connected; see session notes). Related resilience theme:
`.work/backlog/backlog-app-reconnect-churn-timeout-lifecycle-failures.md`
(app side, diagnosed 2026-08-22).
