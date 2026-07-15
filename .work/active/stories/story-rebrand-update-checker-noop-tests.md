---
id: story-rebrand-update-checker-noop-tests
kind: story
stage: done
tags: [rebrand, testing, app, cockpit]
parent: epic-rebrand-external-surfaces-retire-rp-s3
depends_on: []
release_binding: null
gate_origin: review
created: 2026-07-14
updated: 2026-07-15
---

# Add tests for the update-checker no-op default

## Brief

Phase 8 review finding B5. `epic-rebrand-external-surfaces-retire-rp-s3-runtime-update-noop`
is at `stage: review` with all acceptance boxes unchecked — specifically the
required focused tests for the no-op default behavior. The implementation
landed (default manifest URL removed, `fetchLatest()` returns null without
HTTP), but no test proves it.

## Scope

Add focused tests in both Flutter projects:

- `app/test/.../update_checker_impl_test.dart` (new) — assert that default
  `UpdateCheckerImpl().fetchLatest()` returns `null` WITHOUT issuing an HTTP
  request (no network stub invoked). Cover explicit-URL injection still works
  (parsing, silent failure on 404/invalid JSON).
- `cockpit/lib/app/cockpit/.../update_checker_impl_test.dart` (new or extend) —
  same two cases for the cockpit checker.

## Acceptance criteria

- [x] Test proves default `fetchLatest()` returns null without HTTP.
- [x] Test proves explicit-URL path still fetches + parses + returns null on
  failure.
- [x] `flutter analyze` + focused tests pass in both `app/` and `cockpit/`.
- [x] Acceptance boxes checked in the parent runtime-update-noop story.

## Implementation notes

- Added an app test under `app/test/data/update/` with a fake Dio adapter. The
  adapter fails the contract if a default checker makes a request, while
  explicit-URL cases cover valid parsing, 404, and invalid JSON.
- Added a Cockpit test under `cockpit/test/app/cockpit/data/update/`. The
  default case installs an `HttpOverrides` client factory that would throw if
  invoked; explicit-URL cases use a loopback `HttpServer` so parsing and
  silent failures are tested without external network access.
- Verification passed with the repository Flutter SDK: focused tests and
  `flutter analyze` in both `app/` and `cockpit/`.
