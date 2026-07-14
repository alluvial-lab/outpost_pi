---
id: epic-rebrand-to-outpost-pi-en-first-app-ui-review
kind: story
stage: implementing
tags: [rebrand, docs, i18n, app]
parent: epic-rebrand-to-outpost-pi-en-first-app
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Translate app UI prose and review onboarding/update copy

## Scope

Own `app/lib/ui/**` only. Translate PT comments/dartdoc in these six files:

- `app/lib/ui/CLAUDE.md`
- `app/lib/ui/chat/widgets/detail_placeholder.dart`
- `app/lib/ui/onboarding/widgets/welcome_step.dart`
- `app/lib/ui/update/states/update_banner_state.dart`
- `app/lib/ui/update/viewmodels/update_banner_viewmodel.dart`
- `app/lib/ui/update/widgets/update_banner.dart`

Review quoted literals in `welcome_step.dart` and `update_banner.dart` as
complete user-facing phrases rather than mechanically replacing words. Their
current title/body/CTA/update/tooltip strings are already English; preserve or
make a deliberate natural-EN improvement only. Preserve widget keys,
interpolation, `Outpost-Pi`, the `OutpostPi.apk` artifact reference, callbacks,
layout, state handling, and accessibility intent.

## Dartdoc gap manifest

In `app/lib/ui/pairing/viewmodels/pairing_viewmodel.dart`, add intent-level
`///` docs to:

- `PairingTransportFactory` — one-attempt transport factory contract.
- `PairingViewModel` — QR pairing state/lifecycle ownership.

All other ViewModel classes already have class-level purpose dartdoc. Public
widgets outside the six-file translation manifest are Recommended rather than
part of this Always-tier gap-fill.

## Acceptance criteria

- [ ] All six PT-bearing UI files are natural EN.
- [ ] Welcome and update-banner copy is reviewed in context and remains natural
      EN without interaction/layout changes.
- [ ] `PairingTransportFactory` and `PairingViewModel` have meaningful `///`
      docs.
- [ ] Widget keys, interpolation, product/artifact identifiers, callbacks, and
      state behavior are unchanged.
- [ ] No changes outside `app/lib/ui/**`.
- [ ] Touched Dart files are formatted; relevant pairing/update tests pass.
- [ ] The feature-level integrated run can pass `flutter analyze` and
      `flutter test` from `app/`.
