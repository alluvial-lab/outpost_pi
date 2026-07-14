---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-settings-domain-composition
kind: story
stage: implementing
tags: [rebrand, docs, i18n, cockpit]
parent: epic-rebrand-to-outpost-pi-en-first-cockpit-settings
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Translate and document settings domain + composition

## Scope

Translate Portuguese comment/dartdoc prose to English in these owned files:

- `cockpit/lib/app/settings/domain/contracts/cron_gateway.dart`
- `cockpit/lib/app/settings/domain/contracts/daemon_supervisor.dart`
- `cockpit/lib/app/settings/domain/contracts/relay_gateway.dart`
- `cockpit/lib/app/settings/domain/cron_schedule.dart`
- `cockpit/lib/app/settings/domain/entities/cron_job.dart`
- `cockpit/lib/app/settings/domain/entities/daemon_info.dart`
- `cockpit/lib/app/settings/domain/entities/paired_device.dart`
- `cockpit/lib/app/settings/domain/exceptions/daemon_error.dart`
- `cockpit/lib/app/settings/settings_module.dart`

Use bounded replacements inside comments only. Preserve signatures, wire/JSON
values, cron behavior, paths, commands, route/bind semantics, and lifecycle.

## Dartdoc gap-fill

Add meaningful `///` contract docs to exactly these audited Always-tier gaps:

- `DaemonSupervisor.start`, `stop`, `restart`, `startAll`, `stopAll`,
  `restartAll`.
- `CronGateway.listCron`, `addCron`, `removeCron`, `setCronEnabled`.
- `cronResultFromWire` and `daemonStateFromWire`, including their unknown-input
  fallback semantics.

Existing docs on `RelayGateway`, `nextCronRun`, and `buildSettingsModule` are
translated in place. Do not add filler docs to DTO fields or obvious members.

## Acceptance criteria

- [ ] All nine files contain idiomatic English comments/dartdoc and no PT prose.
- [ ] The twelve named Always-tier declarations have intent-bearing `///` docs.
- [ ] Result success/failure, cron preview, unknown-wire fallback, and
      supervisor/relay boundary meaning remain accurate.
- [ ] No declaration, enum/wire value, JSON key, algorithm, route, bind, or
      runtime behavior changes.
- [ ] Scoped PT scan, dart format check, and relevant settings tests pass.
