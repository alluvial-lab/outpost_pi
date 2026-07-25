---
id: gate-security-pair-code-file-preexisting-perms-window
created: 2026-07-24
updated: 2026-07-24
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
