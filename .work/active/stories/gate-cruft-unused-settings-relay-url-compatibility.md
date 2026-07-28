---
id: gate-cruft-unused-settings-relay-url-compatibility
kind: story
stage: implementing
tags: [app, cleanup]
parent: null
depends_on: []
release_binding: null
gate_origin: cruft
created: 2026-07-20
updated: 2026-07-28
---

# Remove unused Settings relay-URL compatibility projection

## Confidence
Low

## Category
compatibility shim

## Location
`app/lib/ui/settings/viewmodels/settings_viewmodel.dart:65`

## Evidence
```dart
/// Compatibility projection for the existing Settings field label.
String get effectiveRelayUrl => effectiveRelayLabel;
```

The only remaining consumer is `app/test/ui/settings/settings_viewmodel_test.dart:321`; production code uses neither `effectiveRelayUrl` nor its compatibility label. The canonical `relayResolution` and `effectiveRelayLabel` already express the supported setting state.

## Removal
Remove `effectiveRelayUrl` and its implementation-bound assertion in the Settings ViewModel test. Keep `relayResolution` as the canonical state projection; no user-visible behavior or compatibility guarantee is removed.
