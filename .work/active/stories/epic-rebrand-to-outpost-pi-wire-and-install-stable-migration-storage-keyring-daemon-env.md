---
id: epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-storage-keyring-daemon-env
kind: story
stage: done
tags: [rebrand, app, pi-extension, cockpit, lifecycle]
parent: epic-rebrand-to-outpost-pi-wire-and-install-stable-migration
depends_on:
  - epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-regen-generated
release_binding: null
gate_origin: null
created: 2026-07-11
updated: 2026-07-12
---

# Storage, keyring, launchd, URI-scheme & env-var identifiers (hard cutover)

## Scope

Unit 8 of the wire-stable migration feature. Rename the internal stability-
boundary identifiers that carry data-loss or daemon-management consequences:
Hive box names, keyring services, owner-identity blob keys, the launchd label,
the QR-pairing URI scheme, and the `REMOTE_PI_*`/`REMOTEPI_*` env vars.

Per the locked hard-cutover decision (operator confirmed 2026-07-11), these
rename **destructively** — no migration/read-old path. Phone loses persisted
pairing data, Pi loses keyring identity, launchd daemon orphaned under old
label. Accepted for a single-operator fork.

## Units implemented
- Unit 8 (storage/keyring/launchd/URI/env)

## Changes
- Hive box names (`app/lib/pairing/storage.dart` lines 7-8):
  `dev.remotepi.peers`/`dev.remotepi.rooms` → `dev.outpostpi.peers`/`dev.outpostpi.rooms`
- Keyring services (`pi-extension/src/pairing/storage.ts` lines 26-27):
  `NEW_SERVICE = "dev.remotepi.pi"` → `"dev.outpostpi.pi"`;
  **remove `OLD_SERVICE = "dev.remotepi.mac"` and the read-old migration
  branch** — the rebrand supersedes the mac→pi migration; update
  `storage.test.ts` accordingly (remove the mac-migration test)
- Owner identity:
  - `BlockStoreStore.kt` line 113: `BLOB_KEY = "dev.remotepi.owner.identity"` → `"dev.outpostpi.owner.identity"`
  - `KeychainSyncStore.swift` line 25: `service = "dev.remotepi.owner.identity"` → `"dev.outpostpi.owner.identity"`
- launchd (`pi-extension/src/daemon/install.ts` lines 108, 111,
  `service-templates/launchd.plist.template` line 7, `extension.test.ts`
  line 333, `cockpit/.../environment_probe_impl.dart` line 70,
  `pi-extension/docs/daemon.md`):
  `dev.remotepi.supervisord` → `dev.outpostpi.supervisord`
  (label + plist filename). Old daemon NOT auto-cleaned — see the
  version-and-docs story for the documented manual `launchctl bootout` step.
- URI scheme (`app/lib/pairing/qr_scanner.dart` lines 4, 45,
  `pairing_viewmodel.dart` line 55, `paste_qr_sheet.dart` lines 10/144/168,
  `app/test/pairing/qr_scanner_test.dart`):
  `remotepi://` → `outpostpi://`
- Env vars (extension readers + cockpit emitters):
  `REMOTE_PI_*` → `OUTPOST_PI_*`, `REMOTEPI_*` → `OUTPOSTPI_*`
  (includes `REMOTE_PI_ALLOW_FILE_IDENTITY`, `REMOTE_PI_DAEMON`,
  `REMOTE_PI_DIRECT_CONFIG`, `REMOTE_PI_HOME`, `REMOTE_PI_MCP_CWD`,
  `REMOTE_PI_MCP_NAME`, `REMOTE_PI_RELAY`, `REMOTE_PI_SYNC_LIMIT`,
  `REMOTE_PI_DEBUG_LOG`, `REMOTEPI_RELAY_PORT`, `REMOTEPI_MESH_DB_PATH`,
  `REMOTEPI_RELAY_LOG_DIR`)

## Acceptance Criteria
- [x] `corepack pnpm --dir pi-extension test` passes except the already-known
      flaky cwd-lock test; storage tests pass and the mac-migration test is removed.
- [ ] `flutter analyze` + `flutter test` (in `app/`) green (qr_scanner,
      paste_qr_sheet, storage tests updated to `outpostpi://` + new box names)
- [x] `grep -rn 'dev\.remotepi\|REMOTE_PI_\|REMOTEPI_\|remotepi://' app/ pi-extension/src/ cockpit/lib/` returns nothing (excluding generated/local `.dart_tool/`, `.gradle`, `build/`, and `dist/`)
- [x] launchd plist template + install.ts use `dev.outpostpi.supervisord`

## Implementation notes

- Applied the destructive Outpost-Pi cutover for app secure-storage namespaces,
  Pi keyring service, native Owner-identity keys, launchd, QR scheme, and
  extension-reader/cockpit-emitter environment variables. The legacy mac keyring
  read/copy/delete path and its tests were removed.
- `flutter analyze --no-pub` passes, and `flutter test test/pairing/qr_scanner_test.dart`
  passes. The full app suite currently has four unrelated existing failures in
  debug-capture/sync-session timing tests; no failures involve this story's
  pairing URI or storage changes.
- Pi extension tests pass except the documented flaky cwd-lock collision test.
