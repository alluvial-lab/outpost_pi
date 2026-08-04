---
id: story-mobile-slash-command-picker-sheet
kind: story
stage: implementing
tags: [app]
parent: feature-mobile-slash-command-invocation
depends_on: [story-mobile-slash-command-extension-action]
release_binding: null
gate_origin: null
created: 2026-08-04
updated: 2026-08-04
---

# App command picker/sheet (mode 1)

Unit D of `feature-mobile-slash-command-invocation` — the second operator-decided
entry mode. A dedicated command-entry UI modeled on the existing quick-actions sheet.

## Change

- `app/lib/ui/chat/quick_actions/**` — a command picker/sheet: browse/search +
  free-text entry. **Phase 1:** free-text command entry + a small set of common
  commands (`/new`, `/reload`, `/outpost-pi …`) invoking the `slash_command`
  action (Unit B). **Phase 2 (follow-up):** full command-catalog enumeration
  (query the extension for all available commands — native + extension-registered
  + skills); needs a new command-catalog wire surface, scoped separately.

## Acceptance

- [ ] Picker lets the user select/type a command → invokes `slash_command`; result
      surfaces in the transcript.
- [ ] Phase-1 common-command set + free-text entry works end-to-end.
- [ ] `flutter test --exclude-tags e2e` green; `flutter analyze` clean.

## Ordering

`depends_on: [story-mobile-slash-command-extension-action]`. Parallel with C.
Phase-2 catalog enumeration is a separate follow-up (needs a wire surface).
