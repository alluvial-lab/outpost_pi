---
id: story-fold-chat-adaptivity
kind: story
stage: implementing
tags: [app, ux]
parent: feature-fold-usability-pass
depends_on: ['story-fold-golden-harness-fidelity']
release_binding: null
gate_origin: null
created: 2026-08-23
updated: 2026-08-23
---

# Chat adaptivity: compact keyboard-landscape, compact narrow headers, wide reading measure

Review findings 6, 7 (chat), 10. Files: `lib/ui/chat/chat_page.dart`,
`lib/ui/chat/widgets/input_bar.dart`, `lib/ui/chat/widgets/message_bubble.dart`.

- Keyboard landscape (797×411 + 280dp inset): top bar (56dp) + composer
  fight for ~131dp → full-width overflow band, no usable transcript.
  Compact-height composer mode when `height - viewInsets.bottom` is tight:
  reduce vertical chrome (the fixed 14/10/14/22 padding around a 38dp send
  action at input_bar.dart:346,927), prioritize input+send, let the
  transcript collapse without overflow.
- Narrow (234dp): header overflow stripes — chat reserves back+info around
  a two-line title and a multi-label status row (chat_page.dart:150-219,
  548-581). Below ~280dp: status collapses to dot + one priority label;
  title single-line ellipsis.
- Wide single-pane (797×411): assistant prose + composer span ~765dp — no
  reading measure. Cap assistant prose and composer in a shared centered
  ~640dp column (user bubbles already cap at 300dp,
  message_bubble.dart:29); code blocks stay full-width scrollable.

## Verification
Widget tests at 234/350/797dp widths and the 797×411+keyboard inset: zero
overflow (story-1 harness now fails on overflow), composer compact-mode
asserted, prose column width asserted <= 640 in wide single-pane. Goldens.
