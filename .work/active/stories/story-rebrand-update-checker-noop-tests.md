---
id: story-rebrand-update-checker-noop-tests
kind: story
stage: drafting
tags: [rebrand, testing, app, cockpit]
parent: epic-rebrand-external-surfaces-retire-rp-s3
depends_on: []
release_binding: null
gate_origin: review
created: 2026-07-14
updated: 2026-07-14
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

- [ ] Test proves default `fetchLatest()` returns null without HTTP.
- [ ] Test proves explicit-URL path still fetches + parses + returns null on
  failure.
- [ ] `flutter analyze` + focused tests pass in both `app/` and `cockpit/`.
- [ ] Acceptance boxes checked in the parent runtime-update-noop story.
