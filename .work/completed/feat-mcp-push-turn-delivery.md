---
id: feat-mcp-push-turn-delivery
kind: feature
completed: 2026-11-20
tags: [pi-extension, docs, research]
created: 2026-11-19
updated: 2026-11-20
---

# MCP push-turn delivery and delivery-mode generalization

Completed (`8e2b6fae9`, review fixes `b7800db0c`). Generalized `pi-extension/skills/agent-network/SKILL.md`, `mesh_server.ts` MCP instructions, `pi-extension/README.md`, `PROTOCOL.md`, and `docs/DECISIONS.md` around push-delivered vs. inbox-drained delivery modes, MCP push-queue retention bounds, and the hybrid local-push / remote-inbox invariant. Added opt-in `--push-deliver` on `outpost-pi claude` (fail-fast exit 1 for both `--push-deliver` and ambient `OUTPOST_PI_MCP_PUSH_DELIVER=1` without `--outpost-mesh-wake`, preserving authority/drain/local-only guards) and `--push-deliver` / `OUTPOST_PI_MCP_PUSH_DELIVER=1` on `mesh_server.ts` using single-source `PUSH_DELIVER_CLI_FLAG` / `PUSH_DELIVER_ENV_VAR` constants, backed by `PushDeliveryTransport` and `createPushDeliveryCoordinator` (`pi-extension/src/mcp/push_delivery.ts`) with a dedicated bounded `pushQueue`, 5s `WakeGate` rate cap, 64 KiB UTF-8 batching, single-flight FIFO async serialization, oversized-envelope and transport-failure rollback to `get_messages` with `pendingDropped` preservation and throwing-`onTransportError` isolation, and synchronous `dispose()` teardown. Recorded settled Part 2b Antigravity (`agy` 1.5.12) clean-env probe findings in `pi-extension/docs/agy-push-delivery.md` and parked follow-ups in `.work/backlog/idea-agy-push-turn-delivery.md` and `.work/backlog/idea-broker-cwd-control-char-sanitization.md`. Verified green across `pi-extension/` (`typecheck`, 71/71 test files / 1,260 passed / 3 skipped, `build`, CLI fail-fast smoke tests), `validate-workbench.py` (0 errors, 0 warnings), and `scripts/check-public-exposure.sh`. Full pre-closure feature record preserved in Git history at `8e2b6fae9`.
