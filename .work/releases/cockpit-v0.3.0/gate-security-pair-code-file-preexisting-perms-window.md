---
id: gate-security-pair-code-file-preexisting-perms-window
created: 2026-07-24
updated: 2026-07-24
stage: done
release_binding: cockpit-v0.3.0
tags: [security]
gate_origin: security
---

# Pair-code seam: pre-existing broader-perms file keeps them during write

Severity: Low (parked per gate_finding_routing).
`pi-extension/src/extension/command_surface/pairing_coordinator.ts:179-186`:
`writeFile(..., {mode: 0o600})` applies the mode only when creating a file.
If the configured path already exists with broader permissions, the token is
written while those permissions remain; `chmod(0600)` happens afterward.
Fix direction: write to an owner-only temp file with 0600 set before secret
bytes land, reject symlinks, atomically rename into place; remove the file
after consumption/expiry. Test-only, opt-in seam — exploitability requires
the var enabled outside the harness plus a local attacker.

## Resolution

Implemented in `implement: pair-code-seam-hardening`: the extension now
exclusive-creates a same-directory `0600` temporary file, writes and syncs the
payload, rechecks that the target is absent/non-symlink, then atomically renames
it into place. A unit test confirms a pre-existing `0644` target is rejected
without writing the generated bearer payload; existing seam coverage confirms no
token is logged.
