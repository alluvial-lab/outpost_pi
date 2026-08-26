---
id: idea-mobile-attachments-files-and-share-target
created: 2026-08-26
updated: 2026-08-26
tags: [app, ux, idea]
---

# Mobile attachments: arbitrary files + Android share-sheet target (residue)

Residue of `idea-mobile-media-attachments-to-session` (archived 2026-08-26:
its premise — no way to attach images/screenshots — shipped via
`attach_sheet.dart` camera/gallery + `UserMessage.images`). The narrower
follow-ups that remain:

1. **Arbitrary file attachments** — not just camera/gallery images; needs a
   check of what the wire (`WireImage`) and the pi-extension ingress side
   actually accept before designing.
2. **Android share-sheet target** — register the app as a share destination
   so content from other apps can be handed to the active agent session
   (relates to `backlog-app-no-outpostpi-deeplink-intent-filter`, active:
   same AndroidManifest intent-filter surface).
