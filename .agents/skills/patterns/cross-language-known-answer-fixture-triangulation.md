# Cross-Language Known-Answer Fixture Triangulation

Generate one deterministic protocol fixture independently, then require every language implementation to reproduce its transcripts, keys, signatures, and wire bytes exactly.

## Rationale

Unit tests that seal and open with the same implementation can preserve a shared bug. The owner-channel KAT uses fixed secrets, nonces, transcripts, and frames from an independent generator, then makes both Dart and TypeScript reproduce the bytes.

## Examples

### Example 1: Independent generator emits deterministic sealed frames
**File**: `protocol/scripts/generate-owner-channel-kat.ts:91-145`
```ts
const frames = [
  {
    dir: "app->pi",
    seq: 1,
    nonce: bytes("000102030405060708090a0b0c0d0e0f1011121314151617"),
    plaintextJson: '{"type":"ping","id":"kat-ping-1"}',
    key: kAppToPi,
  },
  // ...
] as const;

const kat = {
  // ...
  frames: frames.map(({ dir, seq, nonce, plaintextJson, key }) => ({
    dir,
    seq,
    nonce: base64(nonce),
    plaintext_json: plaintextJson,
    sealed_b64: base64(seal(key, nonce, BigInt(seq), plaintextJson)),
  })),
};

writeFileSync(outputPath, `${JSON.stringify(kat, null, 2)}\n`);
```

### Example 2: Dart implementation reproduces fixture bytes
**File**: `app/test/data/transport/secure_channel_test.dart:111-129`
```dart
for (final vector in frames) {
  final key = vector['dir'] == 'app->pi' ? appKeys.send : appKeys.receive;
  final sequence = vector['seq'] as int;
  final sealed = await sealOwnerChannelFrame(
    key: key,
    sequence: sequence,
    json: vector['plaintext_json'] as String,
    nonce: _b64(vector['nonce'] as String),
  );
  expect(base64.encode(sealed), vector['sealed_b64']);

  final opened = await openOwnerChannelFrame(
    key: key,
    frame: sealed,
    lastSequence: sequence - 1,
  );
  expect(opened?.sequence, sequence);
  expect(opened?.json, vector['plaintext_json']);
}
```

### Example 3: TypeScript implementation consumes the same fixture
**File**: `pi-extension/src/transport/secure_channel.test.ts:91-103`
```ts
const highWater = new Map<KatFrame["dir"], bigint>([
  ["app->pi", 0n],
  ["pi->app", 0n],
]);
for (const frame of kat.frames) {
  const key = frame.dir === "app->pi" ? appKeys.send : piKeys.send;
  const restore = _setOwnerChannelNonceSourceForTest(() => b64(frame.nonce));
  try {
    const sealed = seal(key, BigInt(frame.seq), frame.plaintext_json);
    expect(Buffer.from(sealed).toString("base64")).toBe(frame.sealed_b64);
    const opened = open(key, sealed, highWater.get(frame.dir)!);
    expect(opened).toEqual({
      seq: BigInt(frame.seq),
      json: frame.plaintext_json,
    });
    highWater.set(frame.dir, BigInt(frame.seq));
  } finally {
    restore();
  }
}
```

## When to Use
- Cryptographic transcripts, binary framing, canonical encoding, or cross-language protocol algorithms.
- Whenever both endpoints could otherwise pass self-consistency tests while disagreeing on bytes.

## When NOT to Use
- Purely language-local behavior with no shared wire representation.
- Nondeterministic behavior that cannot safely expose a deterministic test seam.

## Common Violations
- Generating expected values by importing one of the production implementations.
- Giving each language its own fixture.
- Testing only round trips rather than exact intermediate keys, transcripts, signatures, and frame bytes.
- Updating fixture and consumers together without reviewing the protocol-level byte change.
