---
id: idea-pi-host-double-mesh-join-ghost
created: 2026-08-22
updated: 2026-08-22
tags: [pi-extension, testing, bug]
---

# Prevent duplicate local mesh joins in the live Pi-host adapter

A fresh isolated two-Pi-host roster run reported each host's active address with
a `#2` suffix while the remote roster contained both the base address and the
`#2` address, for example
`/tmp/outpost-pi-e2e-cwd@outpost-pi-e2e-cwd` and
`/tmp/outpost-pi-e2e-cwd@outpost-pi-e2e-cwd#2`. The live adapter emits
`session_start` and then explicitly calls `outpostPiTestHarness.connect`, so two
concurrent mesh-start paths may pass the `_meshNode == null` guard before either
assigns ownership. The roster-bootstrap assertion now checks that each current
broker-issued counterpart appears rather than conflating this duplicate-local
join with missing cross-PC bootstrap. Diagnose and fence the duplicate join
separately; do not weaken the broker's normal collision handling.
