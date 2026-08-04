---
id: backlog-mobile-new-button-newsession-no-command-ctx
created: 2026-08-03
updated: 2026-08-03
tags: [app, pi-extension, bug]
---

# Mobile "New" button: "newSession unavailable (no command ctx yet)"

## Symptom (operator, 2026-08-03)

Tapping the **New** button on mobile surfaces an error along the lines of
"newSession unavailable (no command ctx yet)" (operator paraphrase; confirm the
exact string during investigation).

## Pinned code path (quick grep, not a full investigation)

- **Throw site:** `pi-extension/src/actions/handlers.ts` —
  `if (!ctx?.newSession) throw new Error(...)` — the "new session" action
  handler aborts when the command context's `newSession` is absent.
- **Trigger (app):** the mobile "New" quick-action runs
  `ActionName.sessionNew` —
  `app/lib/ui/chat/quick_actions/viewmodels/quick_actions_viewmodel.dart`
  (`_runVoid(ActionName.sessionNew, _repo.…)`) → sends the `sessionNew` action
  to the extension → hits the handler above.
- **Command-context binding (extension):** `bindCommandContext` /
  `_rememberCommandContext` (`pi-extension/src/index.ts`) and the tracked
  context in `pi-extension/src/session/sdk_session_projection.ts`
  (`bindCommandContext` / `bindReplacementContext`). "no command ctx yet" =
  none of these has bound a context with `newSession` at the moment the action
  fires.

## Likely cause (to confirm)

A command-context **binding-lifecycle gap**: the app can fire the "New" action
before the extension has bound a command context carrying `newSession`
(e.g. before the first agent turn / `session_start`, or after a context was
cleared but the app still shows New as available). Needs investigation to
confirm exactly when `bindCommandContext` runs vs when the action is allowed to
fire, and whether the app should gate/disable the New button until the context
is armed (there's already a `message_api_armed`/`n { armed }` signal in the
projection that may be the right gate).

## Not done here

Parked only — symptom + pinned path + likely cause. No investigation or fix
performed.
