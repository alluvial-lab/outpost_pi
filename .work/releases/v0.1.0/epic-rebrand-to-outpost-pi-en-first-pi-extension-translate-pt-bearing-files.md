---
id: epic-rebrand-to-outpost-pi-en-first-pi-extension-translate-pt-bearing-files
kind: story
stage: done
tags: [rebrand, docs, i18n, pi-extension]
parent: epic-rebrand-to-outpost-pi-en-first-pi-extension
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
---

# Translate PT-bearing pi-extension source comments

Translate comment and JSDoc prose only in the bounded source set. Do not change
runtime strings, identifiers, protocol frames, behavior, or generated output.

## Files and scope

- `pi-extension/src/index.ts` — translate the extension overview, pairing and
  known-peer reconnect comments; retain the current `/** */` entrypoint docs.
- `pi-extension/src/mesh/siblings.ts` — translate mesh-membership comments and
  add JSDoc to `DiscoverSelfLabelResult` and `DiscoverOptions`.
- `pi-extension/src/mesh/canonical.ts` — translate canonical-JSON contract prose
  without changing its cross-language serialization behavior.
- `pi-extension/src/mesh/canonical.test.ts` — translate test-description/comment
  prose. Replace the non-PT fixture `Renée 🦀` with `Renee 🦀` so the required
  accented-Latin PT scan has no false positive while the emoji continues to
  exercise UTF-8 encoding.
- `pi-extension/src/session/broker_remote.ts` — translate all PT prose and add
  contract JSDoc to `RemotePeerEntry`, `BrokerRemoteOptions`, and `BrokerRemote`.
- `pi-extension/src/session/cwd_lock.ts` — translate all PT prose and add JSDoc
  to `AcquiredLock`, `RefusedLock`, and `CwdLockResult`.

`index.ts` test-only underscore exports and harnesses stay Skip-tier; add no
noise docs there. `canonical.test.ts` stays Skip-tier for JSDoc.

## Acceptance criteria

- [x] The six listed files contain no Portuguese comment prose or accented-Latin
  candidates.
- [x] `canonicalize` behavior and all runtime/wire identifiers remain unchanged.
- [x] New comments are English JSDoc that document contracts rather than types.
- [x] Focused mesh/session tests and the final feature verification pass.

## Implementation notes
- Files changed: `pi-extension/src/index.ts`, `pi-extension/src/mesh/siblings.ts`, `pi-extension/src/mesh/canonical.ts`, `pi-extension/src/mesh/canonical.test.ts`, `pi-extension/src/session/broker_remote.ts`, and `pi-extension/src/session/cwd_lock.ts`.
- Tests added: none (documentation-only change; retained and ran the affected regression tests).
- Discrepancies from design: none; the specified `Renée 🦀` fixture is now `Renee 🦀`, retaining emoji UTF-8 coverage.
- Adjacent issues parked: none.
- Verification: focused canonical/siblings/broker-remote/cwd-lock tests (59 passed); full typecheck, test (837 passed, 3 skipped), and build passed; the required accented-Latin scan produced zero candidates.
