# Outpost-Pi — Relay

A lightweight WebSocket relay server that connects the **Outpost-Pi** mobile app to
`pi-extension` processes running on your Operational System. It handles peer routing and presence
tracking; paired app↔Pi owner `ct` is encrypted and opaque to the relay, while cross-PC Pi↔Pi
envelopes remain relay-readable.

For a full overview of the project, see the
[root README](../README.md).

---

## Protocol & Security

For wire format, identity model, ACK protocol, cross-PC routing, mesh
membership, trust model, and failure modes, see
[PROTOCOL.md](../PROTOCOL.md) at the repo root. It is the canonical reference
for everything the relay enforces on the wire.

---

## How it works

Every device authenticates with an Ed25519 keypair during the WebSocket handshake
(challenge-response). After that, the relay routes messages between peers identified
by their public key. Paired app↔Pi owner `ct` contains a versioned XChaCha20-Poly1305
sealed frame and remains opaque to the relay; cross-PC Pi↔Pi envelope bodies are not
E2E-protected and remain readable to the relay.

---

## Self-hosted relay

Outpost-Pi is local-relay-only: you run your own relay from the
`relay/` source. There is no public/community relay. Running your own means
no third-party relay operator handles your traffic.

### Security considerations

Messages have distinct transport, authentication, and endpoint protections:

- **Transport** — direct relay deployments use cleartext `ws://`. Use `wss://`
  only behind an external TLS-terminating reverse proxy; the reference deployment
  uses plain `ws://` on a LAN/tailnet.
- **Relay authentication and authorization** — challenge-response proves control
  of any advertised Ed25519 key. The relay forwards app↔Pi outer envelopes to
  the requested authenticated peer and room without a pairing lookup; pairing is
  endpoint-enforced, and sealed owner-channel payloads are undecryptable without
  the pairing keys. Only cross-PC `pi_envelope` delivery checks signed mesh
  membership.

Post-pairing app↔Pi owner payloads are protected by an endpoint-established
XChaCha20-Poly1305 channel. The relay forwards the `ct` field as opaque ciphertext,
so a compromised or malicious relay cannot read those commands or responses. The
relay still sees routing metadata, and cross-PC Pi↔Pi envelopes are not E2E-protected
and remain readable to the relay.

**If you handle sensitive work — private code, credentials, proprietary data — we
strongly recommend running your own relay.**

---

## Self-hosted relay (recommended for privacy)

Running your own relay means no third-party relay operator handles your traffic.

### Docker (quickest)

Build from the local `relay/` source, then run:

```bash
docker build -t outpost-pi-relay relay/
docker run -d \
  --name outpost-pi-relay \
  -p 3000:3000 \
  -v outpost-pi-data:/data \
  --restart unless-stopped \
  outpost-pi-relay
```

The relay listens on a **single port** (`3000` by default) and serves three
surfaces at once:

- `GET /` — WebSocket upgrade (the peer protocol)
- `GET /health` — health check (returns `200 OK`)
- `GET / POST /mesh/<owner_pk_hash>` — signed membership versions

Enter the canonical HTTP(S) relay URL in both clients: `http://<your-server-ip>:3000`
for a direct deployment, or `https://<your-server-ip>:3000` when an external
TLS-terminating proxy such as Caddy or nginx fronts the relay. The app and
`pi-extension` convert this value to `ws://` or `wss://` internally when opening
the WebSocket. Legacy persisted or QR endpoints using `ws://`/`wss://` may be
tolerated defensively, but those schemes are rejected at the user-configured
URL boundary.

**`/data` volume**: the relay stores its SQLite database (signed membership
versions) at `/data/mesh.db` inside the container. Mount a named volume (as in
the example above) or a host directory (`-v /srv/outpost-pi:/data`) so the state
survives `docker rm` and image upgrades. Without an explicit mount, Docker
creates an anonymous `/data` volume, so the database survives restarts of that
container but is not a durable, reusable upgrade strategy; clients re-publish
their state at the next mutation if it is lost.

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `OUTPOSTPI_RELAY_PORT` | `3000` | TCP port that serves the WebSocket upgrade, `/health`, and `/mesh/*` (all on the same port) |
| `OUTPOSTPI_MESH_DB_PATH` | `/data/mesh.db` in Docker · `data/mesh.db` (cwd-relative) for bare-metal builds | Path to the SQLite database that stores signed membership versions. The parent directory is created automatically on first boot. The Docker image presets this to `/data/mesh.db` and declares `/data` as a volume — see the volume note above |
| `RUST_LOG` | `info` | Log level filter — e.g. `info`, `debug`, `warn` |

Example with a custom port and logging (volume mount is the same):

```bash
docker run -d \
  --name outpost-pi-relay \
  -p 8080:8080 \
  -v outpost-pi-data:/data \
  -e OUTPOSTPI_RELAY_PORT=8080 \
  -e RUST_LOG=info \
  --restart unless-stopped \
  outpost-pi-relay
```

### Mesh membership endpoint

The `/mesh/<owner_pk_hash>` endpoint stores **Owner-signed** lists of paired Pis,
keyed by `sha256(owner_pk)` in lowercase hex. It enables an app on a new device
(same Apple ID / Google account) to recover its peer list automatically after
restoring the Owner Ed25519 key from iCloud Keychain / Block Store.

The relay verifies every `POST` against the embedded `owner_pk` using Ed25519
and only accepts versions strictly greater than the current one (monotonic).
Bodies are capped at 500 KB. The relay never decides membership — it only
stores what was signed by the Owner. A compromised relay can deny service but
cannot forge membership without the Owner private key.

**Self-hosting note**: the SQLite database at `OUTPOSTPI_MESH_DB_PATH`
(`/data/mesh.db` inside the official Docker image) is your operational
responsibility — make sure `/data` is on a persistent volume and back it up
alongside any other server state. If you lose it, clients re-publish their
current view at their next mutation.

**Storage layout**: SQLite runs in the default rollback-journal mode (NOT
WAL), so only `mesh.db` persists. During a write transaction a transient
`mesh.db-journal` may appear in the same directory and is deleted on commit.
Both files live under `OUTPOSTPI_MESH_DB_PATH`'s parent directory — typically
`/data/` in Docker or `data/` next to the binary on bare metal. The directory
is created automatically on first boot.

### Behind a reverse proxy (HTTPS/WSS)

For production use, put the relay behind a TLS-terminating proxy. Example Caddy config:

```
relay.yourdomain.com {
    reverse_proxy localhost:3000
}
```

Then set the canonical relay URL in both clients to
`https://relay.yourdomain.com`; each client converts it to `wss://` when
opening the socket.

---

## Building from source

```bash
cargo build --release
./target/release/relay
```

```bash
OUTPOSTPI_RELAY_PORT=8080 RUST_LOG=info ./target/release/relay
```

## Running tests

```bash
cargo test
cargo clippy -- -D warnings
```
