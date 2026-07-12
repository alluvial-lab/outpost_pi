---
id: gate-tests-keyring-hard-cutover-ignores-legacy-service
kind: story
stage: done
tags: [testing, rebrand, pi-extension]
parent: null
depends_on: []
release_binding: v0.1.0
gate_origin: tests
created: 2026-07-12
updated: 2026-07-12
---

# Prove the keyring cutover ignores legacy-service identity state

## Priority
High

## Spec reference
Item: `epic-rebrand-to-outpost-pi-wire-and-install-stable-migration-storage-keyring-daemon-env`

Acceptance criterion / locked contract: “these rename **destructively** — no
migration/read-old path. … Pi loses keyring identity” and “storage tests pass
and the mac-migration test is removed.”

## Gap type
Missing test for an explicit destructive-cutover error case.

`pi-extension/src/pairing/storage.test.ts` verifies an existing identity in
`dev.outpostpi.pi` is returned and a missing new-service entry creates one, but
it never seeds a legacy `dev.remotepi.mac` entry and proves the lookup neither
reads nor adopts it. Deleting the previous migration test leaves the rejection
side of the hard cutover unexercised.

## Suggested test
```ts
test("legacy keyring identity is ignored after the destructive Outpost-Pi cutover", async () => {
  const backend = new InMemoryBackend();
  backend.store.set("dev.remotepi.mac|longterm-ed25519", legacyIdentity);
  _setKeyStoreBackendForTest(backend);

  const identity = await getOrCreateEd25519Keypair();

  expect(backend.reads.map(({ service }) => service)).toEqual(["dev.outpostpi.pi"]);
  expect(identity).not.toMatchKeypair(legacyIdentity);
  expect(backend.writes).toContainEqual(expect.objectContaining({
    service: "dev.outpostpi.pi",
  }));
});
```

## Test location (suggested)
`pi-extension/src/pairing/storage.test.ts`

## Fix (2026-07-12)
Added the test "legacy keyring identity (dev.remotepi.mac) is ignored after the
destructive Outpost-Pi cutover" to storage.test.ts. Verifies: only
dev.outpostpi.pi is read (never dev.remotepi.mac), a fresh identity is
generated + written to the new service, the generated key ≠ the legacy key,
and the legacy entry is never deleted (no migration cleanup path). 13/13
storage tests pass.
