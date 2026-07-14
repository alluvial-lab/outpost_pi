---
id: epic-rebrand-to-outpost-pi-en-first-pi-extension-jsdoc-composition-daemon
kind: story
stage: implementing
tags: [rebrand, docs, pi-extension]
parent: epic-rebrand-to-outpost-pi-en-first-pi-extension
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Add JSDoc to composition, commands, and daemon services

Add English `/** */` comments only to the Always-tier gaps listed below. Do not
change implementation, signatures, generated files, or test-only exports.

## Gap-fill inventory

- `src/actions/handlers.ts`: `handleSessionCompact`, `handleSessionNew`,
  `handleThinkingSet`, `handleModelSet`, `handleListModels`.
- `src/config.ts`: `loadConfig`, `saveConfig`, `ConfiguredRelayResolution`,
  `UnconfiguredRelayResolution`, `RelayResolution`. `OutpostPiConfig` remains
  a Skip-tier storage shape.
- `src/daemon/client.ts`: `SupervisorOfflineError`, `callSupervisor`,
  `supervisorOnline` when not already adequately documented.
- `src/daemon/control_protocol.ts`: `encodeRequest`, `encodeReply`,
  `parseReply`; leave the wire DTO shapes Skip-tier.
- `src/daemon/cron_registry.ts`: `CronRegistry`, `saveCronRegistry`,
  `listJobs`, `getJob`, `removeJob`, `setJobEnabled`, `ScheduleValidation`,
  `validateSchedule`, and `nextRunFor` where missing.
- `src/daemon/registry.ts`: `loadRegistry`, `saveRegistry`, `addDaemon`,
  `removeDaemon`, `listDaemons`, and `migrateRegistryNames`; registry record
  shapes remain Skip-tier.
- `src/daemon/rpc_child.ts`: `RpcChild` and its process/lifecycle contract.
- `src/daemon/supervisor.ts`: `decideFireAction` and `Supervisor`.
- `src/daemon/install.ts`: installation/uninstallation and binary-linking
  result contracts plus `installService`, `uninstallService`, `linkCliBinaries`,
  and `unlinkCliBinaries`; omit trivial platform/path constants and helpers.
- `src/extension/command_surface/{commands,control_commands,local_mesh_commands,standalone_cli}.ts`
  and `src/extension/command_surface.ts`: command specifications/ports, command
  adapter classes, and CLI construction/launch functions.
- `src/extension/{composition_root,legacy_ports,owner_multiplexer,ports,relay_transport,runtime_coordinator,types}.ts`:
  exported runtime/port contracts, lifecycle factory functions, control-frame
  decoder, multiplexer decoder/factory, and relay transport factory/error.
  Exclude `testing.ts` as Skip-tier test harness API.

## Acceptance criteria

- [ ] Every listed Always-tier export has concise English JSDoc with lifecycle,
  side-effect, error, or boundary meaning where relevant.
- [ ] JSDoc on ports explains the contract without mirroring TypeScript fields.
- [ ] No code behavior or generated artifact changes.
- [ ] Relevant daemon/extension tests and final feature verification pass.
