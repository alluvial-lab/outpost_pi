---
id: gate-docs-formal-rigor-relay-backpressure
status: superseded
superseded_by: resolved-in-substance (formal-rigor-stack/SKILL.md:60 now documents the bounded 16-frame mailbox)
created: 2026-07-20
updated: 2026-07-24
tags: [documentation]
release_binding: null
gate_origin: docs
---

# Formal-rigor relay backpressure guidance still says mailboxes are unbounded

## Severity
Medium

## Drift category
repo-skill-staleness

## Location
- Doc: `.agents/skills/formal-rigor-stack/SKILL.md:60`
- Contradicting source: `relay/src/handlers/peer.rs:28-30`, `relay/src/resource_limits.rs:9-10`

## Current doc text
> Current relay uses unbounded Tokio mpsc senders; any high-volume producer needs bounded/dedup/drop semantics.

## Contradiction
The relay now sets WebSocket frame/message ceilings at upgrade and creates each authenticated connection with a bounded 16-frame Tokio `mpsc` mailbox. The current wording falsely presents unbounded relay mailboxes as the active implementation.

## Required edit
Replace the backpressure guidance in place with the current bounded-mailbox contract: each authenticated connection has a 16-frame mailbox; delivery is non-blocking drop-newest on saturation and disconnect/reconnect hydration restores authoritative state. Retain the warning against introducing unbounded producers.
