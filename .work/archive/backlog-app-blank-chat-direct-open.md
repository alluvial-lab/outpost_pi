---
status: groom-done
id: backlog-app-blank-chat-direct-open
created: 2026-08-21
updated: 2026-08-21
tags: [app, bug]
---

Promoted to `story-fix-app-blank-chat-direct-open`.

# Blank chat when opening the app directly into an existing session chat

Operator report (2026-08-21): pulling the app up directly into an existing
session chat sometimes shows a blank chat; backing out and re-entering the
session renders it. Related: the session-swallow root cause in
`story-app-send-swallowed-session-identity-unavailable` (hydrate does not
restore active-session state promptly) and parked
`app-hydration-truncated-flag-not-surfaced` — same family: cold open →
route → hydrate sequencing leaves projection empty.

## Work

Instrument/reproduce via the debug capture (sessionGate/connHydrate/
roomSnapshot ordering on cold open into a session route vs re-entry);
suspect the projection rebuild subscribes before hydration lands and never
re-projects on the hydrate event. Likely fixed together with the
session-ref restore defect in the story above.
