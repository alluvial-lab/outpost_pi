---
id: backlog-google-fonts-test-network-noise
created: 2026-08-25
updated: 2026-08-25
tags: [app, testing]
---

# Remove google_fonts network errors from the host test suite

The green `flutter test --exclude-tags e2e --concurrency=2` run for
`story-per-device-slim-release-apk` printed failed fetches for Space Mono
Regular/Bold from `fonts.gstatic.com` around `app_router_test.dart`. The suite
still passed all 956 tests, but expected network failures in a green run obscure
real errors and weaken hermeticity. Extend the existing deterministic font-byte
fixture/client setup beyond golden tests to every widget-test surface that can
resolve `google_fonts`.
