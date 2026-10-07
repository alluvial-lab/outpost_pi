---
id: gate-security-mcp-inbox-unbounded
kind: story
stage: done
tags: [security]
parent: null
depends_on: []
release_binding: v0.13.0
gate_origin: security
created: 2026-10-04
updated: 2026-10-05
---

# Polling-only Claude sessions retain an unbounded mesh inbox

## Severity
Medium

## Domain
API Security

## Location
`pi-extension/src/mcp/mesh_server.ts:255` (`inbox.push(msg)`; inbox declared
`:63`, drained only via `get_messages` `:199-203`)

## Evidence
No count/byte/age ceiling. With channel wake now opt-in (v0.12.1 launcher
safe defaults), an idle polling-only Claude session retains messages
indefinitely; a compromised authorized mesh peer can exhaust the MCP
subprocess memory without any Claude tool approval. Broker forwarding and
ACKs do not bound the retained queue.

## Remediation direction
Bound retained messages by count and bytes with an explicit overflow policy
(drop-oldest + surfaced count), bound each polling response, preserve
polling-only defaults. Release-relevant per scanner (exposure amplified by
this release's polling default); unbound per medium routing — operator may
bind case-by-case.

## Implementation notes (2026-10-05)

- New `pi-extension/src/mcp/inbox.ts`: BoundedInbox (count 1,000 + bytes
  4 MiB, drop-oldest, single-oversize reject, surfaced+reset-on-drain drop
  count). mesh_server rewired: wake edge reads eligible state via
  find/some, get_messages prepends the drop warning. 7 unit tests incl.
  wake-edge reads and drop-counter reset.

## Final-review blocker fixed (2026-10-05, autopilot completion review)

Reviewer (cross-model, fresh context) reproduced two acceptance gaps
against the built artifact and bounced this story; both fixed and
reverified (68 files / 1188 tests green):

1. Unit-not-byte accounting: `.length` (UTF-16 units) admitted ~1.5–3x
   the advertised ceiling (6.3 MB Unicode message under a "4 MiB" cap).
   Fix: `jsonByteSize` (Buffer.byteLength of the compact serialization)
   is now the single size source in BoundedInbox wiring.
2. Pretty-print amplification: depth-2000 bodies rendered ~2.4 GB of
   response text from ~3.6 MB retained (indentation multiplies deep
   nesting combinatorially). Fix: `renderInboxMessage` renders COMPACT
   by contract — drain output linear in retained bytes; regression
   tests pin both (byte rejection of multi-byte oversize; no-indentation
   + linearity across many messages).
