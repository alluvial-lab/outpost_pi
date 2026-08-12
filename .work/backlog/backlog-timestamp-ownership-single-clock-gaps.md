---
id: backlog-timestamp-ownership-single-clock-gaps
created: 2026-08-11
updated: 2026-08-11
tags: [pi-extension, app]
---

# Timestamp-ownership / single-clock gaps (gate-confirmed) -> in-flight arc

## Origin
5 High gate findings (v0.4.0) collapsing to one root: gate-refactor R3+R4, gate-tests T4, gate-cruft C4, gate-docs D3.

## Routes to
feature-canonical-transcript-timestamp-ownership (in-flight, IMPLEMENTING, excluded from v0.4.0). These gaps do NOT block v0.4.0; the in-flight arc exists to close them. Fold this evidence into that arc.

## Gaps
- Tool timestamps have two competing owners: message_end records the persisted SDK message timestamp while tool_execution_start independently creates Date.now() for the same event id; TranscriptEventLog.append is first-writer-wins and the app assumes message_end precedes tool_execution_start -> replay can retain the SDK ts while the live tool frame carries the later wall-clock ts, shifting the bubble after reconnect. (index.ts:1346-1367, sdk_session_projection.ts:563-573, transcript_event_log.ts:14-18, sync_service.dart:1121-1123)
- Canonical render sorting still receives phone-clock timestamps: provider-error history has a server ts but the live error frame omits it (app uses DateTime.now()); agent_end records a ts but agent_done broadcasts without it; pre-tool buffered narration fallback uses DateTime.now() beside a server-timestamped tool request. (transcript_projection.dart:326-333, sync_service.dart:904-912/1143-1147/1310-1324, index.ts:1443-1478)
- Tool timestamp tests bypass the production Dart decoder (app tests inject already-constructed Dart objects via pushRaw; no raw-JSON/cross-language fixture proves ts survives the wire). (codec.dart:20-32, protocol.g.dart:985-1024)
- Projection comment falsely claims a single-clock invariant the shipped feature does not establish.

## Work
The arc must: establish one timestamp owner per tool event; carry the producer-owned ts on error and agent_done and anchor fallback narration to the tool-request ts; add a raw-JSON wire fixture decoded through decodeServer.
