# Pairing lifecycle e2e harness

Run the cross-component headless suite from the repository root:

```bash
e2e/run-pairing.sh
```

The runner starts the real relay image, a narrow HTTP-controlled Pi SDK host,
and pinned Toxiproxy. Flutter tests then drive the app's production pairing,
transport, connection, sync, generated-codec, and Hive paths. It builds no APK
and needs no emulator, phone, model provider, or secrets.

Set `OUTPOST_PI_E2E_RELAY_IMAGE` to exercise another already-built relay image.
The default is `outpost-pi-relay:0.1.0`. Set `E2E_KEEP_STACK=1` to retain the
stack after a failed run for local diagnosis; the default always removes
containers and volumes. `E2E_INFRA_ONLY=1` performs only the service/typecheck
smoke.

All readiness checks are bounded. Test output and service diagnostics name
phases and message types only; they must not print QR URIs, tokens, nonces,
signatures, key material, or transcript contents.
