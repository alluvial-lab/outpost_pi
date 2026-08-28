# Release UAT / smoke gate

A release tag is not cut until an operator has run and acknowledged a live
end-to-end smoke against the deployed release candidate. This is the human
backstop that would have caught the `v0.6.0` non-functional ship (the
`/outpost-pi pair` flow was broken by three integration bugs that all passed
the automated gate suite).

This is a **manual checkpoint**, not an entry in `gates_for_release`. The
agile-workflow `release-deploy` skill invokes each `gates_for_release` entry as
`Skill(skill="agile-workflow:gate-<name>")`; there is no `gate-uat` skill, so a
`uat` slot there would fail to resolve and halt the release. Instead,
`release-deploy` pauses for user action after the automated gates pass and
before tag creation (its "mapping requires user action → pause and prompt"
path), and the operator runs this runbook at that pause.

The durable automation that catches integration regressions going forward is
the checked-in `e2e/run-pairing.sh` harness; this manual runbook is the
independent, sooner backstop.

## Verification posture

**Trust relay logs over the footer/UI for connection truth.** Across all three
`v0.6.0` bugs, the relay debug log (`RUST_LOG=info,relay=debug`,
`OUTPOSTPI_RELAY_LOG_DIR=/data/logs`) was the decisive diagnostic signal — the
TUI footer and app UI reported success while the wire path was broken. A green
footer is not acceptance; an `authenticated` line in the relay log is.

## Building the candidate artifacts

`scripts/release-apk.sh --slim --upload-draft v<version>-rc.<n>` owns every
distributable APK build (never ship from a battery-touched `app/build`).
One-time / per-machine wiring it assumes:

1. `~/.config/outpost-pi/release-upload.keystore.jks` + `keystore.env`
   (mode 0600) — the release signer.
2. `app/android/key.properties` — Gradle-side signing config, **gitignored
   by design and NOT auto-created by the script**. Materialize from the env
   before the first slim build of a machine:
   ```bash
   set -a; . ~/.config/outpost-pi/keystore.env; set +a; umask 177
   printf 'storeFile=%s\nstorePassword=%s\nkeyAlias=%s\nkeyPassword=%s\n' \
     "$OUTPOST_PI_UPLOAD_KEYSTORE" "$OUTPOST_PI_UPLOAD_KEYSTORE_PASSWORD" \
     "$OUTPOST_PI_UPLOAD_KEY_ALIAS" "$OUTPOST_PI_UPLOAD_KEYSTORE_PASSWORD" \
     > app/android/key.properties
   ```
3. Build from the tag (a `git worktree add <dir> v<ver>-rc.<n>` keeps the
   main tree untouched); remove the worktree after — it then contains
   key material.

Output: `outpost-<version>-<code>.apk` (fat debug) + `outpost-<version>-<code>-arm64.apk`
(signed slim release) attached to a **draft** prerelease on the tag;
publishing is the operator gate.

**Publish mechanics (learned 2026-08-27):** never promote a draft via the
API `PATCH draft=false` — the GitHub `latest` marker does not move on that
path (v0.9.0 sat unmarked for a day before anyone noticed). Publish with a
fresh `gh release create <tag> --latest <assets>` (delete the draft object
first if one exists; the tag stays).

**Umask warning:** if key.properties was materialized in the same shell
(`umask 177`), RESTORE `umask 022` before building — flutter's `.dart_tool`
created under 177 is mode-600 (dirs need the execute bit) and pub-get fails
with a misleading Permission denied. The release script now resets umask
defensively; keep the habit anyway.

**Pre-phone no-start guard** (mandatory for toolchain-swap candidates):
`scripts/apk-launch-smoke.sh <apk>` — installs on the e2e emulator (x86_64;
build an x64 variant with `--target-platform android-x64` for the slim's
arch) and proves resumed-first-frame + zero FATAL before the phone touches
the build. Run it on the RELEASE variant (R8/AOT classes) at minimum.

## App↔Pi release smoke (the common case)

For a release that touches the app↔Pi path, the smoke exercises the pairing →
session-hydrate lifecycle end to end on a real deploy:

1. **Relay up** — container `outpost-pi-relay` running; `docker logs
   outpost-pi-relay` shows `authenticated` for a real peer, not just `Up`.
2. **Pi extension up** — `/outpost-pi` footer shows 🟢 connected.
3. **Verified pairing-link association** (Android releases): deploy the
   candidate site's `/.well-known/assetlinks.json`, install the release-signed
   slim APK (not the debug APK), then run:
   ```bash
   adb shell pm verify-app-links --re-verify dev.kevoun.outpostpi
   adb shell pm get-app-links dev.kevoun.outpostpi
   adb shell cmd package resolve-activity --brief \
     -a android.intent.action.VIEW \
     -c android.intent.category.BROWSABLE \
     -d 'https://outpost-pi.kevoun.com/pair#t=AAAAAAAAAAAAAAAAAAAAAA&epk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&n=uat'
   ```
   The domain must report `verified`, and the dummy-token resolution must be
   `dev.kevoun.outpostpi/.MainActivity` without a chooser. Never put a live
   pairing token in an ADB command or shell history. A signing-key rotation
   requires publishing its new SHA-256 fingerprint first; the production
   association intentionally excludes the debug certificate.
4. **`/outpost-pi pair` renders the QR** in the TUI (the actual QR glyph, not
   just the "QR ready" notify).
5. **App scans → `pair_ok` returns** (no 30s timeout).
6. **Session transcript hydrates** in the app — messages stream both
   directions; an outbound user message produces an agent response on the app.
7. **Scanner boundary smoke** (mobile_scanner v7 native
   boundary; added 2026-08-16, first executable at next phone-attached
   checkpoint): on the local emulator `scripts/emulator-scanner-smoke.sh` (boot line + prereqs in story-ci-android-emulator-test-job); on a real phone `cd app && flutter test integration_test/mobile_scanner_boundary_test.dart -d <android-or-ios-device> --tags e2e`.
8. **Phosphor Beacon visual smoke on a real device** (dark + light modes;
   pending since v0.5.0 — themed screenshot retake for the site is tracked by
   `feature-public-flip-branding-and-exposure`): verify app theme renders the
   dual-mode tokens and Space Mono on-device, both appearance modes.

Each step must actually occur; a silent skip is a failure. If any step fails,
do not cut the tag — triage via the relay debug log + the delivery-path debug
log (`OUTPOST_PI_DEBUG_LOG=1` → `~/.pi/remote/debug/delivery.log`), fix, redeploy,
and re-run.

## Other-component releases

For releases touching other components, run the equivalent live capability for
that component:

- **cockpit** — launch the desktop build, connect to a running pi session, and
  exercise the control surface (settings create/rename, control commands).
- **relay-only** — confirm `authenticated` peers, cross-PC forward path, and
  room/presence state via the relay log.
- **site** — `pnpm build` green + the production route renders.

## Stack-currency releases — pertinence retests

When a release's bind set bumps the toolchain or SDK floors (Flutter, pi
SDK, majors of runtime plugins), run the pertinence retests for the
specific deltas in addition to the smoke above. Current set (from the
2026-08-28 v0.10.0 sweep; prune rows when a later bump supersedes them —
see `.work/backlog/backlog-stack-v010-pertinence-residue.md`):

1. **Pixel Fold posture/rotation stress** during cold start, reconnect
   hydration, and active streaming (3.47 Mali/AHB Impeller fixes; Tensor
   GPUs are Mali-family) — watch for crash, black frame, frozen frame.
2. **Gboard text input** (3.47 phantom-Shift fix): shift-lock, Backspace,
   Enter, tap/drag selection in chat input and selectable transcript text.
3. **Debug-log share while streaming** (share_plus 13 off-main-thread I/O):
   share the largest permitted log during active streaming/scrolling; no
   visible stall, byte-identical NDJSON.
4. **pi event-bus scoping** (0.84 listeners scoped + cleaned on
   reload/disposal): full process restart, repeated `/reload` cycles, one
   subagent create/complete/fail sequence — exactly one background
   transition per event, no ghost child-session authority; plus one failed
   extension init + recovery.
5. **pi model catalogs after restart** (0.81/0.84 interactive refresh,
   generation-guarded publication): model get/list/set from the phone with
   healthy and unavailable catalogs; cached models stay usable, stale
   refreshes never overwrite newer state.
6. **Streaming markdown URLs** (gpt_markdown 1.2 bare-URL autolink default):
   long streaming replies with partial/bare URLs and malformed links — no
   shifting tap targets mid-stream beyond the accepted reveal, no layout
   churn in long inline code.

## Acknowledgment

The operator records the ack (a checked item / a recorded `--accept` on the
`release-deploy` resume) before the tag is created. No ack → no tag.

## See also

- [`.work/CONVENTIONS.md`](../.work/CONVENTIONS.md) — `release_uat` convention.
- [`e2e/run-pairing.sh`](../e2e/run-pairing.sh) — the checked-in automated form of this smoke.
- [AGENTS.md — Paired wire changes (deploy together)](../AGENTS.md#paired-wire-changes-deploy-together) — component locations and the paired wire-change deploy order.
