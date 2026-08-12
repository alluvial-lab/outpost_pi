---
id: gate-security-local-ipc-permissions
kind: story
stage: done
tags: [pi-extension, security]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-20
updated: 2026-08-11
---

# Supervisor control socket relies on ambient filesystem permissions

## Severity
Medium

## Domain
Authentication & Authorization / Infrastructure & Deployment

## Relevance
Release-relevant

## Location
`pi-extension/src/daemon/supervisor.ts:183`

## Evidence
```ts
mkdirSync(dirname(supervisorSockPath()), { recursive: true });
...
const server = createServer((socket) => this._onConnection(socket));
server.listen(path, () => resolve());
```

## Issue
The POSIX supervisor creates `~/.pi/remote/` and `supervisor.sock` with the process umask, then accepts control requests without a credential check. With a normal `0022` umask, a newly created directory and Node Unix socket are mode `0755`; if the user's home is traversable and pairing storage has not already tightened `~/.pi/remote/`, another local account can connect. The control protocol includes prompt delivery, daemon start/stop/restart, registration, and cron mutation (`pi-extension/src/daemon/control_protocol.ts:32`), so this is more than metadata disclosure. Normal installs can start the supervisor before any Pi child invokes the pairing-storage helper that later chmods the directory, making the ambient-parent assumption observable rather than guaranteed. Exploitation requires a multi-user host with traversable parent directories, so this is a chained local vulnerability rather than a release-blocking high-severity issue.

The local mesh directories and broker sockets are created through the same default-mode pattern in `pi-extension/src/session/global_config.ts:21` and `pi-extension/src/session/leader_election.ts:98`; remediation should cover the shared IPC boundary rather than only one socket.

## Remediation direction
Create and re-harden all POSIX IPC parent directories as `0700`, chmod bound socket files to `0600`, and add permission regressions that begin from an absent or deliberately loose `~/.pi/remote/`. Keep Windows named-pipe access restricted to the current user with an explicit ACL or a verified platform guarantee. Do not rely on pairing/key-storage startup having run first.

## Implementation notes

- Explicitly create and re-harden POSIX IPC parents/session directories as
  `0700`; harden bound supervisor and broker UDS files as `0600`.
- Windows named-pipe paths remain fileless and skip POSIX chmod operations.
- Added a supervisor regression from a fresh home that checks directory and
  socket modes.
- Changed `pi-extension/src/daemon/supervisor.ts`,
  `src/session/global_config.ts`, `src/session/leader_election.ts`,
  `src/extension/command_surface/local_mesh_commands.ts`, and supervisor test.
- Verified with targeted Vitest (29 tests) and `tsc --noEmit`.

## Implementation status (honest)

**Done — POSIX.** IPC parent/session directories are created and re-hardened
`0700`; bound supervisor and broker UDS files are chmod'd `0600`; a supervisor
regression starts from a fresh home and asserts directory + socket modes.
Verified: 29 targeted Vitest tests + `tsc --noEmit`.

**Not done — Windows.** The remediation direction required restricting Windows
named-pipe access to the current user via an explicit ACL or a verified
platform guarantee. The landed change only skips POSIX chmod on fileless
Windows pipe paths (`src/session/ipc.ts:35-49`); it adds no ACL and no
current-user check. Embedding the username in the pipe name is not a security
boundary, so the Windows half of this finding is an open residual, tracked in
`.work/backlog/backlog-piext-windows-named-pipe-acl.md`. Practical exposure is
low on this fork's macOS/Linux-primary targets; the item stays `done` for its
POSIX scope and the Windows residual is explicitly deferred rather than silently
shipped.

## Audit execution
The release scanner ran inline in the gate orchestrator context as explicitly requested, without a nested scanner; independent-context isolation was therefore reduced.
