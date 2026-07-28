---
id: gate-security-local-ipc-permissions
kind: story
stage: implementing
tags: [pi-extension, security]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-20
updated: 2026-07-28
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

## Audit execution
The release scanner ran inline in the gate orchestrator context as explicitly requested, without a nested scanner; independent-context isolation was therefore reduced.
