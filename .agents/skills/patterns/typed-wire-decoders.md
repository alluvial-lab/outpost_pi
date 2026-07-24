# Pattern: Typed Wire Decoders

## Rationale

Multiple modules ingest untrusted wire payloads and apply the same structure:
1) safe JSON parse, 2) runtime shape checks, 3) typed decode, 4) dispatch/fanout.

Keeping this as explicit helper functions reduces malformed-input failure surface
and makes decoding behavior testable and reusable.

## When to use

Use when handling protocol text coming from relay, mesh, or CLI transport lines
that must be validated before touching typed domain objects.

## When not to use

Do not over-apply this to strictly internal, typed in-memory objects already
owned by trusted code paths.

## Examples

### Example 1: canonical relay ingress boundary decodes once

**File:** `pi-extension/src/protocol/relay_ingress.ts:81-117`

```ts
export function decodeRelayIngress(
  line: string,
  limits: Partial<RelayIngressLimits> = {},
): DecodedRelayIngress {
  const effective = { ...DEFAULT_LIMITS, ...limits };
  const rawBytes = Buffer.byteLength(line, "utf8");
  if (rawBytes > effective.maxRawBytes) {
    throw new RelayIngressDecodeError("too_large", rawBytes);
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(line) as unknown;
  } catch {
    throw new RelayIngressDecodeError("invalid_message", rawBytes);
  }
  if (!isRecord(parsed)) {
    throw new RelayIngressDecodeError("invalid_message", rawBytes);
  }

  if (typeof parsed.type === "string") {
    if (isCrossPcFrame(parsed) && parsed.type === "pi_envelope_in") {
      return { kind: "cross_pc", frame: parsed };
    }
    if (isRelayPostAuthControlFrame(parsed)) {
      return { kind: "control", frame: parsed };
    }
    throw new RelayIngressDecodeError("unsupported_type", rawBytes);
  }

  if (!isRelayOuterEnvelopeCompat(parsed)) {
    throw new RelayIngressDecodeError("invalid_message", rawBytes);
  }
  const outer = parsed;
  const payload = decodeBase64Bounded(outer.ct, effective.maxDecodedPayloadBytes);
  return { kind: "outer", frame: outer, payloadUtf8: payload.toString("utf8") };
}
```

### Example 2: generated-validator-backed client payload decoder

**File:** `pi-extension/src/protocol/relay_ingress.ts:143-149`

```ts
export function decodeRelayClientPayload(payloadUtf8: string): ClientMessage | null {
  try {
    return decodeClient(payloadUtf8);
  } catch {
    return null;
  }
}
```

## Common violations

- Repeated inline `JSON.parse` + type-casts at call sites without centralized guard
  functions.
- Dispatching decoded objects without verifying `type` and runtime field shapes.

## Index entry

- **typed-wire-decoders**: Parse/validate untrusted wire payloads through typed decode helpers before dispatch.
