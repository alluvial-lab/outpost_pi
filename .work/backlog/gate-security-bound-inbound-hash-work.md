---
id: gate-security-bound-inbound-hash-work
created: 2026-09-07
updated: 2026-09-07
tags: [security, app]
release_binding: null
gate_origin: security
---

# Bound diagnostic hashing before allocating oversized relay frames

## Severity
Medium — non-blocking backlog per `gate_finding_routing`.

## Domain
Input validation / resource exhaustion.

## Scope and location
Targeted v0.12.0 rc.2 gate over `49180245a`.
Item: `story-metronome-paired-frame-hash-instrument`.
`app/lib/data/transport/ws_transport.dart:261-271`.

## Evidence
```dart
final rawPayloadBytes = raw is String
    ? utf8.encode(raw)
    : raw is List<int>
    ? raw
    : utf8.encode(raw.toString());
final inbound = transport._recordInbound(rawPayloadBytes);
```

The new callback encodes the entire message and hashes every byte before
checking the pre-auth ceiling at lines 269-297 or entering the post-auth
bounded decoder at lines 301-304. It does this even with no debug-log sink.

The existing boundary deliberately uses `relayUtf8ByteLength` to stop once
the ceiling is crossed *without allocating an attacker-sized encoded copy*
(`app/lib/data/transport/relay_frame_decoder.dart:47-74`). This delta puts a
full UTF-8 allocation and linear hash pass in front of that protection. A
malicious/compromised relay, or an active attacker on a cleartext `ws` path,
can supply a huge pre-auth challenge or post-auth text message and force
extra memory and synchronous isolate work before the established rejection.
Binary input also receives a full unbounded hash pass before classification.

The platform already materializes the WebSocket message; this is an
incremental amplification regression, not a claim that the prior app prevented
that initial allocation. The need to control the relay path and the existing
platform limitation keep this below release-blocking severity.

## Remediation direction
Apply the generated pre-auth/authenticated byte ceiling before allocating or
hashing the full payload; retain the allocation-free early-stop check and
handle binary lengths explicitly. For rejected oversized messages, record a
bounded rejection/count and make hash incompleteness explicit rather than
publishing a misleading comparable full-stream hash. Alternatively use a
bounded streaming hash path with explicit truncation/invalidity semantics.
Do not silently weaken the paired comparison contract or hash truncated input
as though it were complete.

## Suggested verification
Use focused transport tests with an oversized pre-auth message and an
oversized post-auth message. Verify rejection occurs without invoking the
full-payload encoder/hash path (a narrow observable test seam or bounded-work
counter is preferable to a timing assertion), while admitted frames retain
the shared exact hash values. Include operation without a debug-log sink.

## Gate verification
Source-read-only ordering/control-flow analysis; no product source edits,
live-fleet actions, or suite execution.
