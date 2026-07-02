---
id: story-pair-code-qr-not-rendering
kind: story
stage: drafting
tags: [pi-extension, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-02
updated: 2026-07-02
---

# /remote-pi pair shows "QR ready" but no QR code / pairing code printed

## Brief

After the relay-auth-signing fix (extension now signs
`remote-pi-relay-auth-v1\n` ++ nonce), `/remote-pi pair` reaches the
pair-code send and the "QR ready" notify fires, but **no QR ASCII or pairing
code text appears in the pi TUI.** The relay is connected (authenticated) and
`showPairQr` reaches the `sendPiMessage({customType:"remote-pi:pair-code",
display:true})` call — the message just doesn't render.

## Reproduction

1. relay-0.2.0 deployed + extension dist rebuilt with the auth-prefix fix.
2. Fresh pi start; `/remote-pi` connects relay (footer shows 🟢 connected).
3. `/remote-pi pair` → "QR ready — valid until …" notify appears, but the
   expected `📱 Scan to pair:\n\n<ascii QR>\n📋 Or copy…` block is absent.

## What's ruled out

- **Not auth** — relay logs show `authenticated peer=YqWjpYw=`; connection
  stays open.
- **Not the broad send guard** — `_sendPiMessage` was reverted to original
  (send + log on failure); only `_sendRelayStateSnapshot` suppresses.
- **Not a relay issue** — pair-code is a local `sendMessage` to the Pi TUI
  (renders in the chat panel), not a relay send.

## Most likely cause (unverified)

`sdkSessionProjection.sendPiMessage` returns `false` because the projection's
`messageApi` is null at the moment `showPairQr` runs — the Pi session isn't
bound yet. Post-revert, the `console.error` ("Pi rejected message") should now
fire; confirm whether it does.

## Investigation steps

1. **Confirm the error fires.** Run `/remote-pi pair` and check whether
   `[remote-pi] pair-code: Pi rejected message: agent session not bound yet`
   appears. If yes → projection binding is the issue (go to step 2). If no →
   `sendMessage` resolved but didn't render (go to step 3).
2. **Projection binding.** Investigate why `session_start` hasn't armed
   `messageApi` before the pair command runs. Check whether pair should
   wait/buffer until bound, or whether `startRelay`'s `ensureSessionStarted`
   isn't arming the binding. Probe: `sdkSessionProjection.messageApiBinding()`
   at pair time (`sdk_session_projection.ts:537`).
3. **Custom-message rendering.** If `sendMessage` resolved (returned true) but
   nothing rendered, check whether `display:true` custom messages render in the
   current pi version, or whether the `remote-pi:pair-code` customType needs
   registration/handling that changed in the 0.6.0 split.

## Files

- `pi-extension/src/extension/command_surface/pairing_coordinator.ts:326` — the
  `sendPiMessage` call with `customType:"remote-pi:pair-code"`.
- `pi-extension/src/index.ts` — `_sendPiMessage` (the send + log path).
- `pi-extension/src/session/sdk_session_projection.ts:399` — `sendPiMessage`
  returning false; `:537` `messageApiBinding()` probe.

## Context

Full debugging arc in `.work/SESSION-NOTE-2026-07-02-paired-deploy-debugging.md`.
This is the last open issue blocking phone pairing (app APK is built and ready
to sideload once the QR renders).
