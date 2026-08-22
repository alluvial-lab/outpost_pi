---
id: story-e2e-chaos-mesh-lane
kind: story
stage: done
tags: [testing]
parent: feature-e2e-chaos-expansion
depends_on: story-e2e-chaos-fault-vocabulary
release_binding: null
gate_origin: null
created: 2026-08-21
updated: 2026-08-22
---

# Mesh lane: second Pi, cross-Pi delivery

Compose: second pi-host instance (distinct identity/cwd); harness pairing to both. Scenarios: Pi→Pi mesh message delivery (device-visibility), mesh ingress during run (queueing fix device-level), one-Pi fault isolation. Acceptance: mesh scenarios green on device lane; adapter extensions test-support only.

## Integrity
Testing-integrity rules bind: discovered oddities parked with capture+triage evidence (never hidden, never gamed); xfail/skip-link known-open bugs; flip-on-fix wired.

## Verification
Device lane (e2e/run-live.sh semantics) green for whatever this story adds; unit tests where logic is pure; flutter analyze if Dart touched.

## Implementation

- Execution capability: `openai-codex/gpt-5.6-sol` at high reasoning; one
  device-lane owner carried the compose, Pi-host, app harness, and scenario
  boundaries together. Review weight: standard project default; independent
  review is not applicable to this child-story checkpoint.
- Added `e2e/docker-compose.mesh.yml`, extending the canonical test compose with
  `pi-host-b`: a distinct HOME/identity, cwd, pair-code file, service port, and
  Toxiproxy front door. The `mesh` selector in `e2e/run-live.sh` layers the
  override only for this lane, forwards both host URLs to the device, captures
  both host logs, and keeps the normal single-host lanes unchanged.
- Extended the test-support adapters to run the production local-mesh + relay
  bridge path, pair the same device Owner to both Pis, publish signed membership,
  refresh membership deterministically, expose broker-issued identities, and
  gate active turns through explicit defer/resolve barriers. The linked-open
  roster-cache escape hatch bypasses only destination roster/room lookup;
  relay authorization, destination anti-spoofing, local broker injection,
  `SdkSessionProjection` ingress queueing, and owner-channel device visibility
  remain production behavior.
- Added e2e-tagged `app/integration_test/live_mesh_test.dart`. Its runnable test
  proves: (1) A→B relay mesh delivery produces an `AGENT-NETWORK` card on the
  device; (2) ingress during B's active run produces no SDK batch before the
  barrier releases and exactly one mesh batch after `agent_settled`; and (3) a
  preserving Pi-A restart leaves Pi-B owner traffic, reply rendering, selected
  room, generation, and app online/live state unaffected.
- `e2e/run-live.sh mesh` — green in 22 seconds: all three
  `MESH_SCENARIO_PASS` markers emitted; 1 runnable test passed and the known
  post-pair roster-bootstrap cell linked-skipped. Compose startup/health,
  distinct identities, both pairings, signed membership, and both host control
  ports were exercised by the run. Evidence is in
  `.work/session-notes/live-mesh-20260822-green/`.
- `scripts/debug_capture_triage.py <green-capture> --timeline` — swallow=0,
  blank_chat=0, churn_clusters=0, chaos_oracle=0. `flutter analyze` passed with
  no issues. Pi-extension verification passed: typecheck, 56 test files (996
  passed, 3 skipped), and build. `python3 -m unittest e2e.test_live_soak` passed
  12 tests; shell syntax and merged Compose config validation passed.
- Simplification: the second service is an override extension rather than a
  forked base compose; one existing host runtime/server serves both instances;
  obsolete exploratory ACK endpoints and timeout plumbing were removed before
  landing. No protocol or production app behavior changed.
- Adjacent issue parked: `backlog-mesh-post-pair-roster-bootstrap-empty`, with
  capture and bounded structural triage. The exact roster assertion remains in
  a flip-on-fix linked skip; no assertion was weakened or deleted.
- Disk hygiene: every device attempt ended with emulator shutdown and
  `app/build` removal. Final `df -h` reported 37G free, above the 8G floor.
