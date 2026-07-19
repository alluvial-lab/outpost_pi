# Pairing lifecycle e2e harness

Run the cross-component headless suite from the repository root:

```bash
e2e/run-pairing.sh
```

The runner builds the relay from the current `relay/Dockerfile`, starts a narrow
HTTP-controlled Pi SDK host and pinned Toxiproxy, then drives the app's production
pairing, transport, connection, sync, generated-codec, and Hive paths. It builds
no APK and needs no emulator, phone, model provider, or secrets.

Set `OUTPOST_PI_E2E_RELAY_IMAGE` to opt out of the source build and exercise an
already-built relay image. Set `E2E_KEEP_STACK=1` to retain the uniquely named
stack after a failed run for local diagnosis; the default always removes
containers and volumes. `E2E_INFRA_ONLY=1` performs only the service/typecheck
smoke.

Each run uses a distinct Compose project and Docker-assigned host ports. Proxy
initialization is idempotent. All readiness checks are bounded. The failure-mode
suite registers real nonce, signature, QR, key, and transcript canaries, captures
Flutter output plus Pi-host and relay service logs, and fails with only a hashed
fingerprint if any canary appears in diagnostics.
