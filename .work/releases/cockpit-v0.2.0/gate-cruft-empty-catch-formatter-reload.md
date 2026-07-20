---
kind: story
release_binding: cockpit-v0.2.0
parent: null
stage: done
id: gate-cruft-empty-catch-formatter-reload
tags: [cockpit, bug]
depends_on: []
gate_origin: cruft
created: 2026-07-01
updated: 2026-07-20
---

# Empty catch-swallow in formatter reload path

## Location
cockpit/lib/app/cockpit/ui/widgets/file_viewer.dart:368

## Issue
_reloadFromDisk silently ignores all exceptions from readAsString() with an empty catch, masking formatter/read failures and making recovery/debugging harder.

## Recommendation
At minimum log or surface a non-invasive error signal (e.g., debug/info telemetry) when reload fails, while preserving current fallback behavior.

## Implementation (inline, 2026-07-19)

Minimal fix at `cockpit/lib/app/cockpit/ui/widgets/file_viewer.dart`:

- Added `import 'package:flutter/foundation.dart' show debugPrint;` (the
  cockpit-wide convention — see `cockpit_module.dart`, `auto_updater_self_updater.dart`,
  `pi_rpc_process.dart`, `agent_session.dart`).
- Replaced the empty `catch (_) {}` at the end of `_reloadFromDisk()` with
  `catch (e, st) { debugPrint('[file-viewer] _reloadFromDisk failed: $e\n$st'); }`.

Behavior preserved: on failure the method still applies no buffer change (the
  prior silent-fallback outcome), so the editor keeps showing the pre-format
  buffer instead of masking the read/formatter failure as success. The failure
  is now observable in the debug console instead of swallowed.

The unrelated `catch (_) { return null; }` JSON-invalid guard at ~line 351 is
intentional fallback behavior in a different method and is out of scope.

## Verification

- `flutter analyze` could NOT be run in this environment: two stacked
  environment issues block it — (1) the read-only pub-cache
  (`/home/agent/.pub-cache` is on a read-only FS; redirecting `PUB_CACHE`
  to a writable dir is tracked in backlog `env-pub-cache-read-only-blocks-flutter-test.md`),
  and (2) git-over-ssh egress blocked during dependency resolution
  (`Bad owner or permissions on /etc/ssh/ssh_config.d/20-systemd-ssh-proxy.conf` —
  a sandbox egress config issue, not a code defect). Reported, not faked.
- Manual verification: the edit region reads correctly; the import is placed
  adjacent to the other `package:flutter/*` imports; `debugPrint` is the
  established cockpit convention; the change is additive (import + logging)
  with no control-flow alteration beyond capturing the thrown error.

## Review (bounded inline, standalone story)

Standalone story (`parent: null`) → bounded inline review. The fix matches the
recommendation exactly (non-invasive signal, fallback preserved) and uses the
repo's logging convention. The only risk surface is whether `debugPrint` spam
on repeated reload failures could noise the console — acceptable: failures are
not expected on the hot path, and the signal is the point.

Advanced to `done`.
