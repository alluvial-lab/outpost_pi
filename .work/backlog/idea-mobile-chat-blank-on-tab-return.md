---
id: idea-mobile-chat-blank-on-tab-return
created: 2026-07-02
updated: 2026-07-02
tags: [app, bug, lifecycle]
---

# Mobile chat renders blank when tabbing back in; needs back-out + re-enter to rehydrate

## Observed

When switching apps on mobile and tabbing back into the active chat, the
message list sometimes renders **blank**. The user has to back out to the
session list and re-enter the chat to rehydrate the transcript. The
session itself is fine — the data is there; the active chat route just
doesn't re-populate its view on app resume.

## Likely surface (not confirmed — bounded scan only)

`ChatPage` is a `StatelessWidget` (`lib/ui/chat/chat_page.dart:23`), so it has
no `initState`/`didChangeDependencies` to re-run on resume. The app-level
lifecycle hook in `lib/main.dart` (`didChangeAppLifecycleState`) on
`AppLifecycleState.resumed` does:

- `meshSync.startPolling()` + `meshSync.pullOnDemand()`
- `reconcileOnAppResume(...)` → `requestSessionSync`

That resume path reconciles mesh/presence and requests a session sync, but a
bounded scan did **not** find evidence that it forces the active chat
ViewModel to reload its message list from the local store / re-replay history
into the view. If the chat route was constructed from a snapshot and the
underlying stream subscription was paused/dropped while backgrounded, tabbing
back in may leave the view observing a stale or empty state until the route is
re-entered (which is exactly what the back-out + re-enter workaround does).

So the suspected gap: **no chat-view-level rehydrate on app resume** — the
resume path touches mesh/presence/sync but not the active chat route's
message list.

## Distinct from

- `idea-mobile-drop-slow-recovery` — that's about network-drop recovery
  latency. This happens on a plain app-switch (no network change), so it's a
  Flutter lifecycle/view issue, not a reconnect issue.
- `idea-mobile-outgoing-message-swallowed` — send-path data loss; this is a
  render/observe gap, not a send gap.

## Followup at design time

- Reproduce: open a chat with history, switch to another app, tab back. Confirm
  the message list is blank vs. stale-vs-current.
- Trace whether `ChatViewModel`'s message stream is live while the app is
  backgrounded (paused) and whether it recovers on resume, or whether the view
  needs an explicit reload signal on `AppLifecycleState.resumed`.
- Decide the fix layer: should the chat ViewModel subscribe to a resume signal
  and reload from local store, or should the route rebuild on resume? Consider
  the `mounted`-guard and `BuildContext`-after-`await` rules from
  `.agents/rules/code-design.md` (Lifecycle ownership) — a naive reload fired
  from the app-level observer must not touch a disposed chat route.
- Check the `scan-lifecycle` skill's "Flutter async UI guards `BuildContext`
  after `await`" and "working state converges false on every exit path" rules
  when designing the fix — this is a lifecycle-convergence defect.

## References

- `lib/main.dart` — `didChangeAppLifecycleState`, `resumed` branch.
- `lib/ui/chat/chat_page.dart` — `ChatPage` is a `StatelessWidget` (no
  lifecycle hooks to re-run).
- `lib/ui/chat/viewmodels/chat_viewmodel.dart` — `reconnect()`, `_disposed`
  guard; check whether it reloads message list on a resume signal.
- `.agents/skills/scan-lifecycle/SKILL.md` — Flutter async UI + lifecycle
  convergence rules.
- `.agents/skills/flutter-mobile/SKILL.md` — mobile lifecycle, provider/VM,
  async safety.
