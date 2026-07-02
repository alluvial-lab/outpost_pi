# Session note — 2026-07-02 — v0.6.0 shipped + paired-deploy debugging arc

Transient handoff note. Per `.agents/rules/agent-discipline.md` this lives in
`.work/` (transient) and is NOT a durable artifact. Delete when superseded.

## What shipped this session

- **v0.6.0** (repo-level, 116 items) — shipped + pushed. Closes the
  cross-component bold-refactor arc (canonical-session, generated-protocol,
  reachability-contract, transcript-event-log, turn-state-machine). 4 gate
  findings resolved in-scope; 0 blocking remain. Tag `v0.6.0` → pushed.
- **All 5 campaign releases now pushed**: cockpit-v1.6.0, app-v1.2.0,
  relay-0.2.0, extension-0.6.0, v0.6.0.
- **AGENTS.md** gained a durable "Deployment and running" section: component
  locations, paired-wire-change deploy order, `/reload` vs full-restart
  semantics, relay container commands, the VM OOM build fix, sideload steps.

## The paired-deploy debugging arc (the important part)

After shipping, we stood up the relay + extension for the first time. This
surfaced a chain of issues I misdiagnosed **twice** before finding the root
cause. Recording the full trail so it isn't re-derived.

### Symptom 1: `[remote-pi] relay-state: Pi rejected message: agent session not bound yet` spam
- **My first diagnosis (WRONG):** guard checked module-level `_messageApi`/`_pi`
  instead of the projection's `messageApi`. Added a broad guard in
  `_sendPiMessage` to silently suppress unbound sends. This stopped the spam
  but was the WRONG fix — it over-suppressed (see Symptom 3).
- **Reality:** this was a *symptom* of Symptom 2, not the root cause. The relay
  wasn't connecting, so relay-state emits fired against an unbound projection.

### Symptom 2: relay won't connect (footer lies "Relay: on, waiting for first pairing")
- **My second diagnosis (WRONG):** env var `REMOTE_PI_ALLOW_FILE_IDENTITY=1`
  wasn't reaching the pi process; told the operator to restart with the var.
  - Reality: the var WAS set in the active session (pid 158853); the keyring
    fallback was working (identity load succeeded — verified via standalone
    script). The env var was a red herring.
- **The actual root cause (found via relay debug logs):** enable
  `RUST_LOG=relay=debug` on the container → `docker logs` showed
  `WARN relay::handlers::peer: auth failed, closing err=invalid signature` on
  EVERY connect attempt.
  - The deployed relay (0.2.0) verifies the auth signature over
    `remote-pi-relay-auth-v1\n` ++ nonce (domain separation,
    `relay/src/auth/challenge.rs:99,110`).
  - The extension (`pi-extension/src/transport/relay_client.ts:239`) signed the
    **bare nonce** with no prefix → `invalid signature` → relay closed the WS
    right after open.
  - This is the `gate-security-extension-relay-auth-signing-oracle` finding I
    **wrongly deferred** as "pre-existing, not bundle-introduced" when shipping
    extension-0.6.0. It IS bundle-introduced: the relay-0.2.0 deploy requires
    the matching extension change. **This was my error in release triage.**
  - **Fix (committed):** `relay_client.ts` now signs `Buffer.concat([
    RELAY_AUTH_DOMAIN_PREFIX, nonce])`, matching the relay. Verified: relay
    log shows `authenticated peer=...`, connection stays open. 8 tests green.
  - **Debugging lesson:** I verified "connect OK" with a standalone script
    that printed `CONNECTED` — but `relay.connect()` resolves on WS OPEN, before
    auth completes; the auth failure closes asynchronously AFTER. So the
    "success" was a false positive. The relay debug log was the only reliable
    signal. **Always verify auth *stays* open for 2s, not just that connect()
    resolved.**

### Symptom 3: `/remote-pi pair` shows "QR ready" but no QR code / pairing code printed
- **Cause (my own bug):** the broad `_sendPiMessage` guard I added for Symptom 1
  silently swallowed the pair-code QR render too (label "pair-code" routes
  through `_sendPiMessage`). So the "QR ready" notify fired but the actual
  `sendMessage` (display: true) was silently dropped.
- **Fix (committed):** reverted `_sendPiMessage` to original (send + log on
  failure); kept the suppress ONLY in `_sendRelayStateSnapshot` (the one
  telemetry path that was actually spamming). Pair-code + critical sends now
  surface failure loudly.
- **Status: ROOT-CAUSED & FIXED** (story-pair-code-qr-not-rendering). The
  revert was necessary but not sufficient. Root cause was NOT the send guard
  — it was `SdkSessionProjection.bindSessionContext` calling
  `replaceSessionCapabilities(ctx)`, which nulled the `messageApi` armed at
  factory init on every `session_start` (the `session_start` ctx from
  `ExtensionRunner.createContext()` carries no `sendMessage`/`sendUserMessage`).
  Fix: `bindSessionContext` now uses additive `bindCapabilities` (pre-split
  behavior). Regression test added. dist rebuilt. → See story for full grounding.

### Symptom 4 (after the QR fix shipped): app scans QR, connects, then times out
- After restarting pi with the QR-rendering fix, `/remote-pi pair` renders the
  QR. App scans → connects to relay (footer 🟢) → spinning wheel ~30s →
  `"Timed out — make sure /remote-pi is running on your Mac"`.
- **Decisive signal:** `docker logs` (RUST_LOG=relay=debug,info) showed the
  app `authenticated peer=/uV6O0I= room=main` then `disconnected` 30s later
  with **no** `dest (peer, room) not found` warning. Routing succeeded; the
  message reached the Pi and was dropped recipient-side.
- **Root cause:** `OwnerMultiplexer.handleOuterLine` had a recipient-side guard
  `if (outer.room && input.roomId && outer.room !== input.roomId) return;`.
  But the relay's `dispatch_outer` REWRITES the delivered envelope's `room` to
  the SENDER's auth room (anti-spoof). The app always auths in `main`; the Pi
  is in its cwd-room — so the guard always dropped the pair_request (and would
  drop ALL post-pair app traffic too). The relay's `(peer, room)` routing
  already enforced delivery; the recipient-side re-check was redundant and
  wrong.
- **Fix (committed):** removed the guard from `OwnerMultiplexer.handleOuterLine`.
  Regression test added (`makeRelayDeliveredLine` helper + cross-room pair test).
  → See story-pair-request-cross-room-dropped for full grounding.
- **Debugging lesson:** the relay debug log's *absence* of a `dest not found`
  warning was the key — it proved the forward succeeded and the drop was
  recipient-side, not routing. Trust the relay log's negatives, not just its
  positives.

### Symptom 5 (after the cross-room fix): app pairs, then spins (no transcript)
- After restarting pi with the cross-room fix, `/remote-pi pair` renders the
  QR; the app scans and shows "Paired with Android device" — but the session
  never hydrates (spinning, no chat/transcript).
- **Decisive signal:** `docker logs` showed the relay rejecting EVERY frame
  the Pi sends: `invalid relay frame, dropping peer=YqWjpYw= err=invalid
  json: missing field room`. (`YqWjpYw=` is the Pi.)
- **Root cause:** `PlainPeerChannel.send` emitted `{peer, ct}` with NO `room`
  field (a deliberate older defensive hold from MVP — "until relay/app accept
  the field"). But relay-0.2.0's generated `OuterEnvelope` made `room` REQUIRED
  (`pub room: String`, `deny_unknown_fields`), so every post-pair server→app
  frame was rejected with `missing field room` and dropped. This is the
  `to_room required (relay-0.2.0 ↔ extension-0.6.0 sender)` paired wire change
  flagged in AGENTS.md — the extension sender side was never updated.
- **Fix (committed):** `PlainPeerChannel.send` now emits `room: "main"`
  (the app's auth room, for relay routing to `(appPeer, "main")`). The relay
  then rewrites the delivered `room` to the Pi's auth room (anti-spoof), which
  the app's inbound filter accepts. Removed a stale unused `myRoomId` ctor
  param that carried the WRONG value (the Pi's room, not the app's) — emitting
  it would have routed to a nonexistent `(appPeer, piRoom)`. Flipped the
  obsolete `omits room` test. → See story-peer-channel-room-required.
- **Debugging lesson:** the relay log named the EXACT missing field (`missing
  field room`) and the sender (`peer=YqWjpYw=` = the Pi). When the relay
  rejects frames, the error string is the diagnosis — read it literally.

## Current state (what's live)

- **relay**: `remote-pi-relay:0.2.0`, healthy, `RUST_LOG=relay=debug,info`
  (debug logging still ON — can lower to `info` once pairing confirmed).
- **extension**: dist rebuilt with (a) auth-prefix fix, (b) the
  _sendPiMessage revert + _sendRelayStateSnapshot-only suppress. Running pi
  has authenticated to the relay (`authenticated peer=YqWjpYw=` in logs).
- **app**: APK built at `app/build/app/outputs/flutter-apk/app-release.apk`
  (79.9MB, version 1.2.0+7) — NOT yet sideloaded (operator pulls from
  workstation via scp). App build bumped `android/gradle.properties` heap to
  3G + redirected temp off tmpfs (the VM OOM fix — committed? NO, uncommitted
  in app/pubspec.yaml bump; the gradle.properties change may be uncommitted
  too — verify).

## Open follow-up: pair-code QR not rendering

**Symptom:** `/remote-pi pair` → relay connects (auth OK), `showPairQr`
reaches the `sendPiMessage({customType:"remote-pi:pair-code", display:true})`
call, the "QR ready" notify fires, but **no QR ASCII / pairing code text
appears in the TUI.**

**What's ruled out:**
- Not auth (relay log shows authenticated; connection stays open).
- Not the broad guard (reverted; `_sendPiMessage` no longer pre-suppresses).
- Not a relay issue (pair-code is a local `sendMessage` to the Pi TUI, not a
  relay send — it renders the QR in the pi chat panel).

**Most likely cause (unverified):** the `sendMessage` call for pair-code is
returning `false` from `sdkSessionProjection.sendPiMessage` because the
projection's `messageApi` is null at the moment `showPairQr` runs — i.e., the
session isn't bound when pair runs. The `console.error` ("Pi rejected
message") should now fire (post-revert) but the operator should confirm
whether it does. If it fires, the projection binding is the issue; if not,
`sendMessage` is silently failing another way.

**Suggested follow-up scope:**
1. Confirm whether `[remote-pi] pair-code: Pi rejected message: agent session
   not bound yet` now appears in the TUI (it should, post-revert). If yes →
   the projection isn't bound at pair time; investigate why `session_start`
   hasn't armed `messageApi` before the pair command, or whether pair should
   wait/buffer.
2. If no error fires → the `sendMessage` resolved but the custom message
   didn't render. Check whether `display:true` custom messages render in the
   current pi version, or whether the `remote-pi:pair-code` customType needs
   registration.
3. Ground the actual `sendPiMessage` return value at pair time (add a
   temporary log, or probe the projection binding when pair runs).

**File to start in:** `pi-extension/src/extension/command_surface/pairing_coordinator.ts:326`
(the `sendPiMessage` call) and `pi-extension/src/session/sdk_session_projection.ts:399`
(`sendPiMessage` returning false). The `messageApiBinding()` accessor at
`sdk_session_projection.ts:537` is the live probe.

## Lessons for next time (durable)

1. **Gate-finding triage:** when a security/correctness finding touches a
   paired-wire-change path, "pre-existing" is NOT a valid deferral if the
   paired component already shipped the matching requirement. The
   signing-oracle finding was the relay-0.2.0 deploy's required extension
   counterpart; deferring it broke auth. Ground deferrals against the actual
   deploy pairing, not just the file's last-touched commit.
2. **Auth verification:** `connect()` resolving ≠ auth success. WS open
   precedes auth; auth failure closes asynchronously. Verify the connection
   *stays open* 2s+, and check the server's auth log, not just the client's
   resolve.
3. **Broad guards hide bugs:** a suppress in a shared send path
   (`_sendPiMessage`) silently swallowed a critical user-facing render
   (pair-code). Suppress at the call site that's actually noisy
   (`_sendRelayStateSnapshot`), not the shared utility.
4. **Footer ≠ reality:** "Relay: on" reports the state flag, not the WS
   connection. The extension can be in "started" state with a null/
   unauthenticated RelayClient. Trust server logs over the footer for
   connection truth.
5. **Mocked-ctx false greens:** the `session_start replacement contexts …`
   test mocked the `session_start` ctx WITH `sendMessage`/`sendUserMessage`
   attached — but the real SDK ctx (`ExtensionRunner.createContext()`) does
   NOT carry those. The test passed while production was broken. When a test
   exercises a lifecycle binding, ground the mock ctx shape against the actual
   SDK `createContext()` output, not the type union's richest member.
6. **Regression-introducing refactor pattern:** a split that changed an
   additive bind (`bindCapabilities`: only set when value qualifies) into a
   replacing bind (`replaceSessionCapabilities`: unconditional null-else-set)
   silently inverted the semantics for inputs that don't carry the capability.
   When extracting `replaceSessionCapabilities`, audit every caller: the
   `session_start` ctx is NOT a replacement context.

## Uncommitted working-tree state (verify before next session)

- `app/pubspec.yaml` bumped to 1.2.0+7 (committed).
- `android/gradle.properties` heap fix (3G + tmpfs redirect) — **may be
  uncommitted**; verify with `git status`. If uncommitted, commit it (it's
  the VM OOM fix, durable).
- `relay/src/auth/auth_test.rs` — pre-existing working-tree mod (not mine;
  carried from before this session).
- `.key` / `.pem` — local secrets, leave untracked.
