---
id: gate-review-live-harness-actions-fake
created: 2026-08-21
updated: 2026-08-21
tags: [app, testing]
---

# Live-device harness mounts a static ActionsRepository fake (design-deviation decision)

Important finding from the `feature-e2e-live-oddities-suite` standard review
(2026-08-21), parked unbound per the review side-effects contract.

`app/integration_test/support/live_device_harness.dart:327-337,617-646` —
`ChatPage` receives `_StaticActionsRepository` instead of the production
`ActionsRepository`. Possibly reasonable isolation for unrelated quick
actions, but it is a NEW fake inside a feature whose design claims an
all-real boundary — an unrecorded deviation.

## Work

Either swap in the real adapter, or explicitly narrow + document the
all-real claim (record the coverage boundary: quick-actions surface is not
exercised by the live lane). Small; fold into any future live-harness touch.
