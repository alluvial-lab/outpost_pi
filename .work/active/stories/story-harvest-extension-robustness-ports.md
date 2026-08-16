---
id: story-harvest-extension-robustness-ports
kind: story
stage: done
tags: [pi-extension, bug]
parent: feature-upstream-remote-pi-harvest
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-15
updated: 2026-08-15
---

# Extension robustness ports: keyring timeouts, identity precedence, print guard

Four upstream robustness fixes verified present-and-broken in our tree.

## 1. Keyring operation timeouts — upstream `a60526ec`

`pi-extension/src/pairing/storage.ts:75-81`: `NapiKeyringBackend` awaits
`getPassword()`/`setPassword()` directly; on headless/libsecret systems a
hung native call hangs pairing forever. Upstream wraps operations with a
timeout at their `storage.ts:95-122`. Port the bounded wrapper for
read/write/delete across all backends.

## 2. Non-fatal keyring load + no destructive mint — upstream `074c5c5f`

Ours statically imports `AsyncEntry` (`storage.ts:5`) — under Bun the native
binding load can throw and take the extension down; upstream lazy-loads at
their `storage.ts:147-195`. Also: upstream rejects minting a new identity
over existing pairings (`:420-421`); ours can mint a file identity at
`storage.ts:270-293` without consulting `peers.json`. Port both, adapted to
Outpost-Pi names/env, KEEPING our O_EXCL mint path and peer-store locking.

## 3. File-first identity precedence — upstream `f6a92d86` (identity half)

Ours can generate a new keyring key at `storage.ts:255-257` before checking
the file at `:270`; upstream checks the file identity first (`:220-230`).
(Dedupe half not needed — our `runtime_coordinator.ts:37-82` is stronger.)

## 4. Print-mode relay auto-start guard — upstream `964c9005`

`pi -p`/`--print` hangs on the auto-started relay socket; upstream guards
`process.argv` at their `index.ts:2103-2107`. Ours auto-starts from session
lifecycle (`index.ts:1672-1681`) with no print-mode guard. Add it.

## Verification

`corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`; unit
tests for the timeout wrapper (fake hanging backend) and precedence order;
cite upstream shas in the commit message.

## Implementation

- Execution capability: sol/high for identity- and security-bearing keyring behavior.
- Landed bounded read/write/delete credential operations, lazy native binding load with a non-fatal file fallback, file-first identity resolution, and paired-roster guards that refuse both unreadable-keyring and empty-alternate-keyring replacement mints while preserving the exclusive file mint and peer-store lock.
- Added actionable `PairedIdentityMissingError` handling at relay startup and suppressed lifecycle auto-start in SDK print mode plus legacy `-p`/`--print` invocations.
- Key files: `pi-extension/src/pairing/storage.ts`, `pi-extension/src/index.ts`, and `pi-extension/src/extension/composition_root.ts`, with focused coverage in their matching tests.
- Verification: `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build` passed (56 files, 982 passed, 3 skipped). The first full run exposed the pre-existing timing-sensitive audit-rotation test without its `.1` file; its focused rerun passed, and the complete gate then passed on rerun.
- Deviations: the print guard uses authoritative `ctx.mode === "print"` and retains the upstream argv check as compatibility fallback; no runtime-coordinator, peer-locking, or O_EXCL mint behavior was replaced.
- Adjacent issues parked: none.
