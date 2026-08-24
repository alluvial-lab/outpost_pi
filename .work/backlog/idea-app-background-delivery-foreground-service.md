---
id: idea-app-background-delivery-foreground-service
created: 2026-08-24
updated: 2026-08-24
tags: [app, idea]
---

# Background delivery while phone is dozed/screen-off

From overnight capture app-capture-2026-08-24T03-27-16 (0.7.0 install day):
21:30→23:14 offline window is the app backgrounded/dozed — Android kills
the socket and the app only reconnects on foreground. Messages/captures
cannot arrive while the phone sleeps. If the operator wants push-like
delivery, options: foreground service (persistent notification), or
FCM-style push wake. Product decision, not a bug. Deliverability note:
0.7.0's capture upload already proves the wake path works when the app is
open.
