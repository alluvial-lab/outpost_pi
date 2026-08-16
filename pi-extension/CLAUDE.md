# Outpost-Pi — Pi Extension (Node + TypeScript)

Extension for the [Pi coding agent](https://github.com/earendil-works/pi) that
adds the `/outpost-pi` slash command. It embeds the Pi SDK
(`@earendil-works/pi-coding-agent`) and exposes it to the relay through
WebSocket.

It is part of Outpost-Pi's **cross-PC coding-agent mesh**: each PC loads this
`ExtensionFactory` in Pi with an Ed25519 Pi key in the system keyring; optional
daemon mode runs background Pi processes under `pi-supervisord`. The phone is
the initial QR authenticator; among sibling PCs owned by the same Owner, a
local UDS broker plus Pi-to-Pi relay forwarding over WS routes opaque
`<cwd>@<name>` addresses, prefixed `<pc>:<cwd>@<name>` cross-PC.

For protocol, identities, ACKs, cross-PC routing, and the trust model, see
[`../PROTOCOL.md`](../PROTOCOL.md) (the repository's canonical document).

## Stack

- Node 20+ / TypeScript ^7.0.2
- **Module system**: ESM only (NodeNext). Imports use the `.js` extension even in `.ts` files
- Package manager: **pnpm** (do not use npm/yarn)
- Crypto/auth: Ed25519 via `@noble/ed25519` for Pi/Owner identities, pairing signatures, and relay challenge-response. The app↔Pi owner channel has app-layer E2E encryption: signed ephemeral X25519 ECDH in the pair handshake (`@noble/curves`), HKDF-SHA256 directional keys, XChaCha20-Poly1305 frames (`@noble/ciphers`) — see `src/transport/secure_channel.ts` and `PROTOCOL.md`. Cross-PC Pi↔Pi traffic is NOT E2E (relay-visible).
- Pi-secret storage: `@napi-rs/keyring` (macOS Keychain / desktop Linux libsecret / Windows Credential Manager). Headless Linux without D-Bus falls back to `~/.pi/remote/identity.json` (`chmod 0600`) with a warning — install GNOME Keyring/KWallet for real hardening.

## Commands

In the sandbox (`dev-vm`), `/home/agent/.cache` is read-only and pnpm 11.x fails
with `[ERR_SQLITE_ERROR] unable to open database file` unless its store/caches are
redirected. `/home/agent/.npmrc` is a broken character device (the harmless
`EACCES` warning can be ignored). Always prefix commands with repository-local
environment variables:

```bash
cd pi-extension
export PNPM_HOME=~/projects/outpost_pi/.pnpm-store
export npm_config_cache=~/projects/outpost_pi/.npm-cache
export XDG_CACHE_HOME=~/projects/outpost_pi/.xdg-cache
corepack pnpm install --store-dir ~/projects/outpost_pi/.pnpm-store   # if node_modules is missing
corepack pnpm typecheck   # tsc --noEmit, must pass with zero errors
corepack pnpm build      # tsc -> dist/
corepack pnpm dev        # tsx src/index.ts
corepack pnpm test      # full Vitest suite; IPC tests use isolated temporary paths
corepack pnpm exec vitest run <path/to/test.ts>   # targeted tests
```

See [`../.agents/skills/pi-extension-typescript/SKILL.md`](../.agents/skills/pi-extension-typescript/SKILL.md) for the rationale.

## Relay configuration

Resolution order (precedence):

1. `process.env.OUTPOST_PI_RELAY` — escape hatch for CI/ops
2. `~/.pi/remote/config.json` (`{ "relay": "..." }`) — persisted through
   `/outpost-pi set-relay <url>`
3. Without either source, the relay is unconfigured; `/outpost-pi` explains
   how to configure it before opening a connection.

Slash commands:

- `/outpost-pi set-relay <http://… | https://…>` — writes the URL to
  `~/.pi/remote/config.json`. Validation rejects `ws://`, `wss://`, empty
  strings, and malformed URLs (the extension internally converts http(s)→ws(s)
  when opening the WebSocket).
- `/outpost-pi status` — shows relay status and, when unconfigured, instructs
  the user to run `/outpost-pi set-relay <url>`.

`_cmdStart` calls `resolveRelayUrl()` and opens a socket only for a configured
resolution (`env` or `config`).

## Important dependencies

- `@earendil-works/pi-coding-agent` — Pi SDK (`AgentSession`, `SessionManager`, `ModelRegistry`)
- `ws` — WebSocket client

## Conventions

- **Strict TS**: `"strict": true`, no `any` except where unavoidable (use `unknown` + narrow)
- **Imports**: `import { foo } from "./bar.js"` (extension required in ESM)
- **Top-level await** is allowed by ESM
- **Errors**: `class XxxError extends Error` for named classes; throw early at the boundary
- **Logging**: `console.log` is acceptable in the MVP; later migrate to `pino` or similar

## Must not do

- Do not write CommonJS (`require`, `module.exports`)
- Do not commit `dist/` (already in the root `.gitignore`)
- Do not implement ad hoc E2E outside the established owner channel (`src/transport/secure_channel.ts`, suite `outpost-pi-owner-channel-v1`); any new payload-encryption surface must go through `PROTOCOL.md` and explicit dependencies
- Do not introduce a dependency that is not ESM-friendly

## Orchestrated mode

If you receive a prompt beginning with `[ORCH:<task-id>]`, read
`../.orchestration/INSTRUCTIONS.md` before taking any other action. This marker
indicates that another agent is coordinating the work and has specific rules
(where to write the result, do not commit, and so on).
