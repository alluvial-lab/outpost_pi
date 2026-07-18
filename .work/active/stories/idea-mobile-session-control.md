---
id: idea-mobile-session-control
kind: story
stage: drafting
tags: [app, pi-extension]
parent: feature-mobile-native-session-process-control
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-07-18
---

# Mobile app: session control and command surface gaps

Random thoughts from operator use of the mobile app.

## Bugs / gaps

- **"New Session" does not clear the chat log.** Tapping New Session starts a new
  pi session but the on-screen message history carries over, so the user can't
  tell they're in a fresh session and the transcript looks stale. The chat log
  should reset when a new session is created.
- **Slash commands are unusable from mobile.** There's no way to enter/discover
  slash commands (`/new`, `/help`, etc.) on the mobile keyboard surface. This
  blocks a lot of pi interaction that relies on slash commands. One concrete
  consequence: **`/reload` can't be run from mobile.** Since `/reload` is the
  path to pick up extension installs and updates into a running session, this
  means extension lifecycle changes sometimes block the mobile workflow — the
  user has no mobile-native way to reload the extension/sessions and pick up new
  or updated extensions. Worth treating a mobile `/reload` affordance as the
  high-value slice of any slash-command surface work.
  - **Updated motivation (2026-07-08):** `/reload` is also the recovery path
    for the stale-ctx lockout (`story-fix-stale-ctx-messageapi-rearm-on-
    reload`). When a session replacement invalidates the extension's
    `messageApi`, mobile-only operators cannot `/reload` to rebind it — the
    only phone-side affordance is `session_new` (quick actions), which
    *does* rebind via `withSession` but **discards the current conversation**.
    A `/reload` button in the same quick-actions menu as `/new` would give a
    context-preserving recovery: re-fire `session_start` against the loaded
    module (factory re-init re-arms a working `messageApi`) without starting
    a fresh session. This is distinct from the full process-restart in
    `idea-mobile-restart-pi-session-affordance` (which picks up a rebuilt
    `dist/`); `/reload` is the lighter, in-process rebind.
- **New messages don't auto-scroll the chat to the bottom.** When a new message
  arrives (or is sent), the chat window stays at its current scroll position
  instead of scrolling down to show the latest message, so the user has to
  manually scroll to follow the conversation.
- **Can't scroll back through much of the chat history.** Scrolling up through a
  session's chat log is limited — sometimes only the agent's most recent turn is
  reachable and earlier messages are missing/unreachable in the scrollable
  transcript. Could be a render windowing issue, history not being retained in
  the widget, or the scroll view clipping/limiting the loaded messages.

## Design

This story is the implementation unit **Quick Actions session-control
ergonomics**. Keep its scope to the already typed mobile actions: `New
session` (with its post-ACK local transcript reset), `Compact context`, and the
existing model/thinking selectors. Clarify the New session confirmation and
keep all controls room-scoped through `IActionsRepository`; do not create a
free-form slash-command input.

The following observations are explicitly deferred from this feature: `/reload`
(the mobile surface must not imply it reloads `dist/index.js`), spawning new Pi
processes or choosing a cwd, auto-scroll/history depth, hidden-tool status
telemetry, and general slash-command parity. Those need their own design or
belong to the chat-resilience work. The separate process-restart affordance is
implemented by `idea-mobile-restart-pi-session-affordance`, which depends on
this story's shared Quick Actions contract.

## UX/UI polish

- **No feedback when tool calls are hidden.** With tool calls collapsed/hidden in
  the chat, it's not obvious whether a sent message has actually gone through or
  whether the agent is still thinking. There's no clear "thinking / working"
  vs "idle / waiting" indicator tied to the current message state, so the user
  can't tell if they should wait or re-send.
- **Missing terminal-style status info.** The mobile chat has none of the
  terminal UX pi normally surfaces — no context window % used, no token counts,
  no cost/usage feedback. Bringing some of that status telemetry onto the mobile
  surface would help users gauge session health and when to start a new session.

## Feature requests

- **Spawn new pi sessions from mobile.** Beyond the existing New Session behavior,
  the mobile app should be able to actually launch new pi sessions on the remote
  box (not just switch between already-known sessions).
  - Stretch goal: let the user **pick a cwd** when spawning the new session, so a
    fresh session can start rooted in a chosen project directory rather than
    wherever the daemon/extension defaults.
