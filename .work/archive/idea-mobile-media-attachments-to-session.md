---
id: idea-mobile-media-attachments-to-session
created: 2026-08-25
updated: 2026-08-26
tags: [app, pi-extension, ux, idea]
status: superseded
superseded_by: image attachment shipped (attach_sheet camera/gallery; UserMessage.images) — narrower residue re-parked as idea-mobile-attachments-files-and-share-target; groom 2026-08-26
---

# No way to attach files/screenshots in-app to send to the agent session

Operator pain (2026-08-25, while reporting a UI bug): can't attach files or
screenshots in the app — had to export to the workstation and drop into the
repo `debug/` folder manually, the same friction debug captures had before
`feature-debug-capture-delivery`.

## Options at scope time

- Extend the capture-upload channel to ad-hoc MEDIA: a share-sheet target
  ("Send to Outpost-Pi session") + in-app attach affordance; the extension
  already reassembles bounded uploads atomically to `<cwd>/debug/` — same
  machinery with image mime + size caps (a 1-2MB PNG budget vs the 2MiB
  ring cap; maybe larger for media, or compressed client-side).
- Natural pairing with `idea-mobile-artifact-viewing` (bidirectional:
  artifacts down to the phone, media up to the session) and
  `feature-mobile-slash-command-invocation` (command surface).
- Android share-sheet intent-filter would also cover screenshots from
  anywhere (system screenshot → Share → Outpost-Pi).

Related: `idea-mobile-artifact-viewing`, `backlog-app-no-outpostpi-deeplink-intent-filter`
(the intent-filter groundwork serves both).
