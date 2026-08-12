---
id: backlog-piext-windows-named-pipe-acl
created: 2026-08-11
updated: 2026-08-11
tags: [pi-extension, security]
---

# Windows named-pipe IPC lacks an explicit ACL / current-user restriction

## Origin

Deferred residual of `gate-security-local-ipc-permissions`. That finding's
remediation required restricting Windows named-pipe access to the current user
via an explicit ACL or a verified platform guarantee. Only the POSIX half
landed (`0700` directories, `0600` UDS files). Windows pipe paths are fileless
and skip POSIX chmod, but no ACL or current-user check was added — the username
embedded in the pipe name is not a security boundary. Documented here so the
deferral is tracked rather than lost (the parent finding records the scope cut
in its "Implementation status (honest)" section).

## Location

- `pi-extension/src/session/ipc.ts:35-49` — Windows pipe naming.
- Shared IPC boundary also covers the supervisor control socket and broker sockets.

## Severity

Medium — same chained-local-vuln class as the parent finding. Low practical
exposure on this fork's macOS/Linux-primary targets; becomes relevant if Windows
is shipped as a target or the host is multi-user Windows.

## Work

Add a Windows named-pipe security descriptor (current-user-only ACL) or a
verified platform guarantee, and add a Windows-path regression mirroring the
POSIX permission tests. Re-evaluate severity at that point.
