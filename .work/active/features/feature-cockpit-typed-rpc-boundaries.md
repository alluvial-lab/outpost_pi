---
id: feature-cockpit-typed-rpc-boundaries
kind: feature
stage: done
tags: [cockpit, refactor, protocol]
parent: null
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-15
updated: 2026-07-17
reviewed: "2026-07-17 (standard, gpt-5.6-sol fresh-context → ready; 1 nit parked: rpc_smoke.dart prints `Instance of 'RpcJsonObject'` — non-blocking, cosmetic smoke-tool diagnostic)"
---

# Cockpit: typed value objects at RPC domain boundaries

## Brief

Two gate findings in the Cockpit domain layer describe RPC payloads crossing
into domain events as raw `Map<String, dynamic>` blobs, navigated by string
keys deep in business logic — the ad-hoc-map-at-a-boundary anti-pattern the
`.agents/rules/code-design.md` fail-fast rule targets. This feature replaces
them with typed value objects parsed at the boundary:

- `gate-refactor-boundaries-ambiguous-map-rpc-event` — `RpcToolStart.args` and `RpcMeshRevoked.details` carry untyped wire blobs into domain events
- `gate-refactor-boundaries-ambiguous-map-rpc-gateway-respondui` — `RpcProcessGateway.respondUi` requires callers to pass a raw `{value|confirmed|cancelled}` map in a domain port

## Simplification opportunity

Define typed DTOs/value objects at the RPC→domain boundary; parse once, pass
typed objects downstream. Reduces the drift surface and moves validation to the
edge. No public-surface behavior change beyond stricter typing.

## Source

Promoted from backlog by `scope` (2026-07-15). 2
`gate-refactor-boundaries-ambiguous-map-rpc-*` findings from the v0.6.0 release
`gate-refactor` (boundaries library).

## Refactor Overview

Refactor-design pass (2026-07-16). Both findings current; risk differs.
`RpcToolStart.args` structurally valid (raw map flows rpc_event → transcript_event → transcript_message → _ToolCard), though the "deep string-key navigation" rationale is overstated — production consumers preserve + JSON-encode the payload rather than interpreting tool-specific keys. `RpcMeshRevoked.details` is unused (`AgentSession` ignores the event at `agent_session.dart:703-704`) but should remain opaque (the canonical schema intentionally permits arbitrary `details`). `RpcProcessGateway.respondUi` raw map leaks through `AgentProcessController` → `AgentSession` → `UiResponder` → `PiRpcProcess` wire spread.

Existing boundary pattern: hand-written typed domain values + adapter-owned serialization (`RpcDataMapper`, `PiControlCommand`/`PiRpcProcess`, `PairEvent`). Generated Dart does NOT cover cockpit-control; upstream Pi tool args + `extension_ui_response` have no useful generated Dart contract — follow the established hand-written value-object pattern without changing schemas/codegen.

## Black-box boundary (behavior changes that must NOT be in this refactor)

- Adding runtime rejection, changing malformed-input degradation to `RpcUnknown`/failure, tightening the protocol schema, or validating tool-specific keys.
- Making tool-specific fields or mesh detail fields required.

Those route to feature-design. The plan is pure refactor ONLY if parsing preserves current fallback: non-map tool args → empty object; absent/non-map mesh details → `null`; emitted UI response JSON byte-for-byte equivalent; no runtime rejection.

## Refactor Steps

### Step 1: Carry opaque RPC objects through typed domain values
**Priority:** High | **Risk:** Medium | **Source Lens:** missing abstraction / pattern drift / elimination
**Files:** new `cockpit/lib/app/cockpit/domain/value_objects/rpc_json_object.dart`, `domain/entities/rpc_event.dart`, `domain/entities/transcript_event.dart`, `domain/entities/transcript_message.dart`, `data/adapters/rpc_event_mapper.dart`, `data/adapters/rpc_data_mapper.dart`, `ui/session/agent_session.dart`, `ui/widgets/agent_transcript.dart` + focused tests
**Story:** `gate-refactor-boundaries-ambiguous-map-rpc-event`

**Current State:**
```dart
// domain/entities/rpc_event.dart:60-68
final class RpcToolStart extends RpcEvent {
  const RpcToolStart({required this.toolCallId, required this.toolName, required this.args});
  final String toolCallId; final String toolName; final Map<String, dynamic> args;
}
// :277-280
final class RpcMeshRevoked extends RpcEvent {
  const RpcMeshRevoked({this.details});
  final Map<String, dynamic>? details;
}
// data/adapters/rpc_event_mapper.dart:31-36
args: _asStringMap(json['args']),
// transcript path re-expresses as maps at transcript_event.dart:119-132, transcript_message.dart:39-50
```

**Target State:**
```dart
final class RpcJsonObject {
  RpcJsonObject._(Map<String, Object?> values) : values = Map<String, Object?>.unmodifiable(values);
  static final empty = RpcJsonObject._(const <String, Object?>{});
  static RpcJsonObject? tryFromWire(Object? value) {
    if (value is! Map) return null;
    return RpcJsonObject._(value.map((key, item) => MapEntry(key.toString(), item)));
  }
  final Map<String, Object?> values;
}
// RpcToolStart.args: RpcJsonObject; RpcMeshRevoked.details: RpcJsonObject?
// mapper: args: RpcJsonObject.tryFromWire(json['args']) ?? RpcJsonObject.empty
// details: RpcJsonObject.tryFromWire(message['details'])
// CockpitToolRequested.args + ProjectedToolMessage.args -> RpcJsonObject
// _ToolCard: final argsText = args.values.isEmpty ? '' : jsonEncode(args.values);
```
Both live + `get_messages` replay construct the same value object. Replace `RpcDataMapper._asObjectMap` (`:257-262`) with the same boundary conversion.

**Implementation Notes:**
- Copy + shallowly freeze at construction; JSON-decoded nested values unchanged (no recursive normalize/validate).
- Preserve current key coercion to strings from `_asStringMap`.
- Carry the wrapper through the complete transcript path (don't unwrap immediately in `AgentSession:636-647` — that just moves the raw-map boundary one layer).
- Remove `_asStringMap` + `_dynamicMap` after all live + replay paths use the wrapper.
- Retain `RpcMeshRevoked.details` as opaque optional even though unused (removing saves one field but drops the mapped data).
- Do NOT add tool-specific subclasses or mesh-detail fields (tool args = open upstream Pi payload; mesh details = unconstrained by canonical schema).
- Update immutability assertion `test/data/rpc_data_mapper_transcript_projection_test.dart:95-113` to inspect `tool.args.values` (preserve caller-mutation-can't-alter-projection proof).
- Extend `rpc_event_mapper_test.dart:43-87`: tool args retain all keys/values; non-map → `RpcJsonObject.empty`; map details retained; absent/non-map details → `null`.

**Acceptance Criteria:**
- [ ] `flutter analyze` zero issues; `flutter test` passes.
- [ ] `RpcToolStart`/`CockpitToolRequested`/`ProjectedToolMessage`/`_ToolCard` no longer expose tool args as `Map<String, dynamic>`/`Map<String, Object?>`.
- [ ] `RpcMeshRevoked.details` is `RpcJsonObject?`, not raw map.
- [ ] Live `tool_execution_start` + replayed `get_messages` tool calls produce the same typed arg value.
- [ ] Existing tool-card JSON text unchanged for same input.
- [ ] Non-map args still degrade to empty; absent/non-map details still degrade to `null`.
- [ ] No protocol schema, wire discriminator, runtime rejection, or user-visible behavior changes.

**Rollback:** Revert the value-object + restore map fields + `_asStringMap`/`_asObjectMap`/`_dynamicMap`. Independently reversible (no persisted/wire data change).

### Step 2: Replace UI response maps with a sealed domain response
**Priority:** High | **Risk:** Medium | **Source Lens:** missing abstraction / pattern drift
**Files:** new `cockpit/lib/app/cockpit/domain/entities/rpc_ui_response.dart`, `domain/contracts/rpc_process_gateway.dart`, `data/rpc/pi_rpc_process.dart`, `ui/session/agent_process_controller.dart`, `ui/session/agent_session.dart`, `ui/widgets/agent_transcript.dart`, `test/data/pi_rpc_process_control_test.dart` + 4 `RpcProcessGateway` test fakes
**Story:** `gate-refactor-boundaries-ambiguous-map-rpc-gateway-respondui`

**Current State:**
```dart
// domain/contracts/rpc_process_gateway.dart:63-71
Future<Result<void, RpcError>> respondUi(String id, Map<String, dynamic> response);
// ui/widgets/agent_transcript.dart:23-25
typedef UiResponder = void Function(String id, Map<String, dynamic> response, String label);
// :868-923
_respond(<String, dynamic>{'cancelled': true}, 'cancelled');
_respond(<String, dynamic>{'confirmed': false}, 'No');
_respond(<String, dynamic>{'confirmed': true}, 'Yes');
_respond(<String, dynamic>{'value': v}, v);
// data/rpc/pi_rpc_process.dart:160-164
final command = <String, dynamic>{'type': 'extension_ui_response', 'id': id, ...response};
```

**Target State:**
```dart
sealed class RpcUiResponse { const RpcUiResponse(); }
final class RpcUiValueResponse extends RpcUiResponse { const RpcUiValueResponse(this.value); final String value; }
final class RpcUiConfirmationResponse extends RpcUiResponse { const RpcUiConfirmationResponse(this.confirmed); final bool confirmed; }
final class RpcUiCancelledResponse extends RpcUiResponse { const RpcUiCancelledResponse(); }

Future<Result<void, RpcError>> respondUi(String id, RpcUiResponse response);
typedef UiResponder = void Function(String id, RpcUiResponse response, String label);
// _respond(const RpcUiCancelledResponse(), 'cancelled'); etc.
// PiRpcProcess serializes (only layer that knows wire keys):
static Map<String, Object?> _schemaUiResponse(String id, RpcUiResponse response) {
  final payload = switch (response) {
    RpcUiValueResponse(:final value) => <String, Object?>{'value': value},
    RpcUiConfirmationResponse(:final confirmed) => <String, Object?>{'confirmed': confirmed},
    RpcUiCancelledResponse() => <String, Object?>{'cancelled': true},
  };
  return <String, Object?>{'type': 'extension_ui_response', 'id': id, ...payload};
}
```

**Implementation Notes:**
- Keep `id` as separate correlation arg; response object = only the mutually exclusive payload.
- Thread `RpcUiResponse` unchanged through `AgentSession.respondUi` (`:714-720`) + `AgentProcessController.respondUi` (`:229-232`).
- Keep `answerLabel` presentation-only (must not enter RPC serialization).
- Do NOT add runtime validation or throw for response/request-method mismatches (UI already chooses the correct variant; this step makes those construction sites explicit).
- Add `@visibleForTesting` serialization helper adjacent to `schemaControlPromptForTesting` (`:461-463`), or extract an adapter-local codec if less test-only exposure.
- Assert exact output for: string value, confirmation true/false, cancellation.
- Update test fakes mechanically to accept `RpcUiResponse`; don't broaden to `Object`/`dynamic`.
- No canonical protocol/schema edit (upstream Pi JSONL response shape; change is only to Cockpit's internal port).

**Acceptance Criteria:**
- [ ] `flutter analyze` zero issues; `flutter test` passes.
- [ ] No production `respondUi`/`UiResponder` signature accepts `Map<String, dynamic>`.
- [ ] UI controls construct only `RpcUiValueResponse`/`RpcUiConfirmationResponse`/`RpcUiCancelledResponse`.
- [ ] Adapter serialization produces exactly: `{"type":"extension_ui_response","id":id,"value":value}`; `{...,"confirmed":true|false}`; `{...,"cancelled":true}`.
- [ ] `PiRpcProcess` remains the only layer that knows those wire keys.
- [ ] No new runtime rejection, error path, protocol change, or visible label change.

**Rollback:** Revert the sealed response classes + restore the map parameter through widget/session/controller/gateway/adapter/test fakes. Wire format unchanged (no migration).

## Implementation Order

1. `gate-refactor-boundaries-ambiguous-map-rpc-event` — introduce opaque JSON-object value, carry tool args/revocation details through complete incoming-event + transcript path.
2. `gate-refactor-boundaries-ambiguous-map-rpc-gateway-respondui` — introduce sealed UI response, centralize outgoing wire serialization in `PiRpcProcess`.

One feature-owning implementation worker for both steps. Existing child stories are sequential verification checkpoints, not separate ownership units.

## Implementation Summary

Both boundary refactors are implemented without changing the Cockpit wire
contract or runtime fallback behavior:

- Added `RpcJsonObject` with shallow top-level immutability and boundary
  conversion. Tool args and mesh-revoked details now remain typed through live
  events, history replay, transcript events, projection, and tool-card JSON
  rendering. Non-object args still use the shared empty object; absent or
  non-object mesh details remain `null`.
- Added sealed `RpcUiResponse` variants and threaded them through the gateway,
  process controller, session, and transcript UI. `PiRpcProcess` is the sole
  serializer for `value`, `confirmed`, and `cancelled` wire keys; labels remain
  presentation-only.
- Updated focused mapper, projection immutability, UI serialization, session,
  workspace, and gateway fake coverage.

Verification from `cockpit/`:

- `PUB_CACHE=/home/agent/projects/outpost_pi/.pub-cache ~/projects/outpost_pi/.tools/flutter/bin/flutter analyze lib test` — passed.
- Focused RPC mapper/transcript/UI/process/workspace tests — passed (34 tests).
- `PUB_CACHE=/home/agent/projects/outpost_pi/.pub-cache ~/projects/outpost_pi/.tools/flutter/bin/flutter analyze` — passed.
- `PUB_CACHE=/home/agent/projects/outpost_pi/.pub-cache ~/projects/outpost_pi/.tools/flutter/bin/flutter test` — passed (243 tests).
