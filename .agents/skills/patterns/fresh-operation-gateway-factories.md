# Pattern: Fresh Operation Gateway Factories

## Rationale

A process- or session-backed gateway has mutable lifecycle state and cannot be
safely shared between independent operations. Define a small factory contract in
the domain and inject it at composition so each caller receives a fresh gateway
that owns exactly one process, agent, terminal, or pairing attempt.

## When to use

- A gateway starts or owns a process, stream, native resource, or other
  operation-local lifecycle.
- Concurrent operations require isolated request correlation or cancellation.
- A UI/domain consumer must depend on a contract rather than a `data/` adapter.

## When not to use

- The dependency is intentionally a shared, stateless service or a singleton
  resource with its own explicit concurrency policy.
- A factory only disguises a cheap immutable value with no lifecycle ownership.

## Examples

### Pairing operation factory

`PairingGatewayFactory` creates one gateway per pairing attempt; the returned
instance owns the temporary Pi process and its cancellation path.

**File**: `cockpit/lib/app/core/domain/contracts/pairing_gateway.dart:30`
```dart
abstract class PairingGatewayFactory {
  /// Create a fresh gateway for one ephemeral pairing attempt.
  ///
  /// The caller owns cancellation of the returned gateway and its process.
  PairingGateway create();
}
```

### Revoke operation factory

The revoke flow uses the same factory boundary, while each produced gateway
creates and tears down its own ephemeral process for one command.

**File**: `cockpit/lib/app/core/domain/contracts/revoke_gateway.dart:22`
```dart
abstract class RevokeGatewayFactory {
  /// Create a fresh gateway for one ephemeral revoke operation.
  ///
  /// Each returned gateway starts and tears down its own Pi process when
  /// [RevokeGateway.revoke] runs.
  RevokeGateway create();
}
```

### Per-agent RPC factory

An agent session receives a fresh RPC gateway, isolating process lifecycle and
request correlation from other agents.

**File**: `cockpit/lib/app/cockpit/data/rpc/pi_rpc_process_factory.dart:10`
```dart
class PiRpcProcessFactory implements RpcGatewayFactory {
  const PiRpcProcessFactory(this._config);

  final PiSpawnConfig _config;

  @override
  RpcProcessGateway create() => PiRpcProcess(_config);
}
```

### Per-terminal PTY factory

The terminal composition follows the same shape: every factory call creates a
new native-PTY owner.

**File**: `cockpit/lib/app/cockpit/data/terminal/pty_terminal_gateway_factory.dart:8`
```dart
class PtyTerminalGatewayFactory implements TerminalGatewayFactory {
  const PtyTerminalGatewayFactory();

  @override
  TerminalGateway create() => PtyTerminalGateway();
}
```

## Common violations

- Sharing one process-backed gateway across independent operations, causing
  cancellation, stream events, or request replies to cross operation boundaries.
- Instantiating a `data/` gateway in UI code instead of injecting the domain
  factory contract.
- Returning a cached instance from a factory whose contract promises a fresh,
  lifecycle-owned operation.
