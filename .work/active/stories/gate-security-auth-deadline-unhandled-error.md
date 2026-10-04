---
id: gate-security-auth-deadline-unhandled-error
kind: story
stage: done
tags: [security]
parent: null
depends_on: []
release_binding: v0.12.1
gate_origin: security
created: 2026-10-04
updated: 2026-10-04
---

# Cancelled handshakes can emit an unhandled auth-deadline exception

## Severity
Low (marked blocking-by-judgment: reproduced defect in code new to this
release, not ambient hardening)

## Domain
Error Handling & Logging

## Location
`app/lib/data/transport/ws_transport.dart:285-290` (auth-deadline timer)

## Evidence
Cancellation completes the challenge completer, but the deadline timer stays
armed until the cleanup `finally` runs; when an endpoint withholds the HTTP
upgrade, cleanup can remain pending (sink.close not settling), so the timer
fires and completes a never-awaited completer with an error — an uncaught
async exception (scanner reproduced on loopback with shortened deadlines).
Application termination was not established.

## Remediation direction
Disarm the deadline timer when cancellation or failure cleanup begins
(cancelConnect / closeConnectResources), not only in the settle `finally`;
the timer then only fires while the handshake phase is genuinely live.

## Fixed (2026-10-04)
Deadline timer disarmed at the top of both `cancelConnect` and
`closeConnectResources` (failure-cleanup start), keeping the settle-`finally`
cancel for normal paths. Transport suites green (53 tests across 6 files),
analyze clean.
