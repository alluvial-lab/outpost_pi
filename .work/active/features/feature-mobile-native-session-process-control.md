---
id: feature-mobile-native-session-process-control
kind: feature
stage: review
tags: [app, pi-extension, daemon, workflow]
parent: epic-remote-session-resilience-refactor
depends_on: [feature-remote-pi-fork-vendor-and-mobile-surface]
release_binding: null
gate_origin: null
created: 2026-07-15
updated: 2026-07-18
---

# Mobile: native Pi session and process control

## Brief

Two backlog items describe the mobile operator's inability to drive Pi
session/process lifecycle from the phone — the TUI's slash-command surface is
unusable from mobile, and there is no affordance to fully restart the Pi
process (required to pick up a rebuilt `dist/index.js`, since `/reload` does
NOT re-import the module). The mechanism already exists internally
(`EXIT_DAEMON_FRESH_SESSION` exit 42 → supervisor respawn) but isn't exposed as
a mobile action:

- `idea-mobile-session-control` — mobile app: session control and command surface gaps (`/reload`, `/new`, spawn new pi sessions from mobile)
- `idea-mobile-restart-pi-session-affordance` — mobile: no way to fully restart the Pi process (fresh session + relay) from the phone

## Simplification opportunity

Expose the existing `EXIT_DAEMON_FRESH_SESSION` RPC + `session_new` action
through a mobile-facing control surface; don't re-implement process management.
Depends on `feature-remote-pi-fork-vendor-and-mobile-surface` (drafting) for
the mobile-surface scope it shares.

## Source

Promoted from backlog by `scope` (2026-07-15) as a child of
`epic-remote-session-resilience-refactor`. 2 `idea-mobile-*` items. Related to
the drafting `feature-remote-pi-fork-vendor-and-mobile-surface`.

## Design

### Design decisions

1. **Expose a deliberately small control set.** The mobile surface keeps the
   existing `Compact context`, `New session`, `Model`, and `Thinking` controls
   in Quick Actions. This feature adds only `Restart Pi process` to that
   surface; it does not attempt to mirror the TUI slash-command catalog, add
   arbitrary command entry, or add mobile spawning/cwd selection. Compact,
   model, and thinking are already typed action surfaces and remain unchanged
   except for layout/copy as needed.
2. **Use the existing Quick Actions bottom sheet.** It is already reachable
   from the chat input, is scoped to the selected room, and already owns the
   confirmation and error-toast patterns for `session_new`. Restart sits next
   to New session in a clearly separated process/session group, with danger
   styling and a destructive icon rather than a new settings page or a
   dedicated session route.
3. **Reuse `session_new`; do not add `session_restart`.** The restart tile is a
   distinct mobile intent and confirmation copy, but it calls the existing
   `IActionsRepository.newSession()` path and therefore sends the canonical
   `session_new` frame. In daemon mode the extension's existing branch sends
   `action_ok`, resets its session projection, then exits with
   `EXIT_DAEMON_FRESH_SESSION` (42); the supervisor respawns the fresh process.
   No wire discriminator, relay route, or process-management implementation is
   introduced.
4. **Do not expose `/reload`.** The documented `/reload` hook re-fires
   `session_start` on the loaded module and does not re-import `dist/index.js`.
   Presenting it as an extension-update control would be misleading. A future
   context-preserving in-process rebind would need a separately named contract;
   it is not folded into this feature. Likewise, the backlog's broader slash
   command, auto-scroll, transcript-depth, telemetry, and spawn-cwd requests
   are explicitly out of scope here.
5. **Confirm both destructive intents, with different promises.** New session
   says that the conversation is cleared and offers `Cancel` / `Start new`.
   Restart says that the current conversation is cleared, the Pi process will
   restart (for a supervised/daemon Pi), the phone may disconnect briefly, and
   it will reconnect; it offers `Cancel` / `Restart Pi`. Compact and model /
   thinking changes remain one-tap actions. On an interactive, non-daemon Pi,
   the same wire action can only perform the existing in-process new-session
   behavior, so the restart copy must say “on a supervised Pi” rather than
   silently promising a process respawn.

### Lifecycle and interaction contract

The two controls share the existing request correlation and ACK contract:

1. The user confirms from Quick Actions; the sheet is dismissed before the
   dialog's async result is awaited.
2. The app sends `session_new` with the active `(peer, room, session_id)` and
   waits for `action_ok` or `action_error`. A cancelled dialog sends nothing.
3. New session clears the local active transcript only after `action_ok`.
   Restart does the same local clear after the ACK, then shows a short
   “Restarting Pi — reconnecting…” message. A rejection, timeout, or send
   failure does not clear the transcript and is surfaced through the existing
   messenger/error path.
4. In daemon mode the ACK must be sent before the extension schedules exit 42.
   The app then renders the normal `reconnecting` / `offline` status rather
   than treating the expected socket close as an action failure. The
   supervisor's successor reuses the paired relay identity and room; the app
   trusts the authoritative room/session snapshot and `session_sync` after
   reconnect instead of a sticky local “restarted” boolean.
5. The UI must remain safe if the app is backgrounded or the reconnect takes
   longer than expected. Reconnect hydration, not the transient toast, is the
   source of truth for the resulting session and transcript.

### Implementation units

#### 1. Quick Actions session-control ergonomics

- **Maps to:** `idea-mobile-session-control`
- **Files:** `app/lib/ui/chat/quick_actions/widgets/quick_actions_sheet.dart`,
  `app/lib/ui/chat/quick_actions/viewmodels/quick_actions_viewmodel.dart`,
  existing Quick Actions widget/ViewModel tests, and only the existing action
  repository test seam if a regression assertion is needed.
- **What it does:** Keep the canonical compact/new/model/thinking actions in
  one room-scoped menu, clarify the New session copy, and reserve the process
  control slot/group without creating a second slash-command surface.
- **Acceptance:** New session remains a confirmed action; its local transcript
  reset occurs only after a successful `session_new` ACK; errors leave the
  transcript intact; `/reload`, arbitrary slash commands, and spawn/cwd are not
  presented; the existing model/thinking/compact actions still work.

#### 2. Full-process restart affordance

- **Maps to:** `idea-mobile-restart-pi-session-affordance`
- **Files:** the Quick Actions sheet and its ViewModel/state seam under
  `app/lib/ui/chat/quick_actions/`, plus the existing daemon/session action
  adapter and focused extension tests under `pi-extension/src/` if the current
  branch needs a regression guard. No new protocol type is expected.
- **What it does:** Add the dangerous `Restart Pi process` tile and confirmation,
  delegate it to the existing `session_new` sender, clear local state only on
  ACK, and show reconnecting feedback while allowing the normal connection
  state machine to recover.
- **Acceptance:** Confirm/cancel behavior is deterministic; the tile cannot be
  double-submitted while busy; the app sends exactly `session_new`; daemon mode
  ACKs before exit 42 and respawns with the paired room/identity; an interactive
  fallback is described honestly rather than claimed to be a process restart.

#### 3. Cross-surface restart/reconnect verification

- **Maps to:** new story
  `feature-mobile-native-session-process-control-reconnect-verification`
- **Files:** `app/test/data/actions/actions_repository_test.dart`,
  `app/test/ui/chat/quick_actions/quick_actions_sheet_test.dart`, relevant
  reconnect/session-sync tests, and focused `pi-extension/src/**/*.test.ts`
  coverage for the daemon action ordering and fresh-session publication.
- **What it does:** Lock down the smallest useful action, confirmation, ACK,
  expected disconnect, reconnect hydration, and stale-transcript behavior
  without introducing sleeps or weakening assertions.
- **Acceptance:** Tests cover action send/correlation and rejection, both
  confirmation dialogs, no reset before ACK, local reset after ACK, daemon
  ACK-before-exit ordering, and successor room/session hydration. A manual
  daemon-backed phone smoke is recorded separately when a live supervisor is
  available.

### Implementation summary

Implemented the three planned units in the existing mobile Quick Actions
surface. Compact, New session, Model, and Thinking remain the only session
controls alongside the new danger-styled `Restart Pi process` affordance. Both
New session and Restart use separate confirmations; Restart explicitly limits
process-respawn language to supervised Pis and explains transcript loss plus the
expected brief reconnect. Confirmation cancellation sends nothing, failures
preserve the local transcript, and local reset plus restart feedback happen only
after the matching `action_ok` resolves the canonical `session_new` request.
No `/reload`, `session_restart`, arbitrary slash-command, spawn API, wire type,
or pi-extension production change was introduced.

Reconnect remains owned by the existing ConnectionManager/SyncService state
machine and authoritative room/session hydration. The restart snackbar is
transient feedback only; it is not a second source of session truth.

## Verification

- `flutter analyze lib test` — passed with no issues.
- `flutter test --concurrency=1` — passed (755 tests).
- Targeted action-repository and Quick Actions tests — passed, including
  matching ACK/rejection, session-id binding, both destructive confirmation
  paths, controlled ACK-gated reset, and reconnect feedback.
- `flutter build apk --debug` — attempted; blocked before compilation because
  the Gradle wrapper lock under `/home/agent/.gradle` is read-only.

## Testing strategy

The minimum evidence is at the boundaries, not a screenshot-only test: preserve
(or add) the repository test that proves `newSession()` emits the generated
`SessionNew` frame and resolves only on the matching ACK; widget-test cancel,
confirm, busy, success, and failure paths for both destructive controls; and
extension-test the daemon branch's `action_ok` → reset → scheduled exit-42
ordering. Reconnect tests must assert authoritative successor metadata and an
empty/new transcript projection, including a late old-session frame being
ignored. Do not add a new wire contract merely to make the restart label testable.

### Risks

- **Highest risk:** the expected process exit is also the app's transport
  interruption. The action must be acknowledged before exit, and the app must
  distinguish expected reconnecting from a rejected action while still relying
  on authoritative hydration if the phone misses the transient close.
- **Mode ambiguity:** `session_new` does not carry a daemon capability bit. If
  an interactive Pi is exposed to the same mobile surface, it cannot perform a
  process respawn. This design keeps the wire unchanged and uses explicit
  “on a supervised Pi” copy; a capability advertisement or separate semantic
  action is parked until there is a real non-daemon mobile use case.

### Rollback

Remove the restart tile and its ViewModel/widget wiring, reverting to the
existing Quick Actions surface. Because the feature reuses `session_new` and
adds no wire or persistence format, app rollback needs no relay/extension
migration; any extension test-only guards can be reverted independently.
