---
id: story-e2e-chaos-clock-version-skew
kind: story
stage: done
tags: [testing]
parent: feature-e2e-chaos-expansion
depends_on: [story-e2e-chaos-fault-vocabulary]
release_binding: null
gate_origin: null
created: 2026-08-21
updated: 2026-08-22
---

# Clock skew + version-skew drills

Exploratory: libfaketime on relay/pi-host containers (auth TTL, heartbeat, watermark logic under skew); version-skew drill = run relay at previous tag vs current extension (paired-wire-cut class). Bounce-allowed if container constraints block faketime — land findings. Acceptance: at least one skew dimension exercised with invariants held or oddities parked; blockers documented.

## Integrity
Testing-integrity rules bind: discovered oddities parked with capture+triage evidence (never hidden, never gamed); xfail/skip-link known-open bugs; flip-on-fix wired.

## Verification
Device lane (e2e/run-live.sh semantics) green for whatever this story adds; unit tests where logic is pure; flutter analyze if Dart touched.

## Implementation

- Execution capability: `openai-codex/gpt-5.6-sol` at high reasoning; direct exploratory implementation because both drills share the existing Compose/pairing harness but require serial image construction and evidence capture.
- Review weight: standard project default; not applicable independently because this is a child-story checkpoint.
- Added a test-only libfaketime layer (`e2e/services/faketime.Dockerfile`) and Compose override (`e2e/docker-compose.clock-skew.yml`) without changing either production image. `scripts/clock_skew_drill.sh` builds the ordinary relay/Pi-host images, layers libfaketime, runs relay at +2h and Pi-host at -2h, excludes monotonic clocks from faketime, crosses the relay's first 25-second heartbeat, checks health/auth continuity, writes bounded evidence, and always tears down its unique Compose project.
- Clock evidence: `.work/session-notes/clock-skew-20260822/report.md` records measured offsets +7200s/-7199s, one authenticated connection, zero disconnects across 30 seconds, and healthy Pi-host state after the heartbeat boundary. Nonce/signature authentication held with four hours of peer skew; heartbeat and mesh-auth TTL remained sound because their implementations use monotonic time. No oddity was found.
- Added `scripts/version_skew_drill.sh`: selects the previous unified semantic release, exports only that tag's `relay/` tree, builds an isolated image, and runs the current checkout's full app + extension pairing/protected-channel suite against it under a bounded 20-minute timeout. The release workflows publish app/cockpit artifacts but no relay container image, and the local previous-release image was absent, so source-tag construction is the reproducible path.
- Version evidence: `.work/session-notes/version-skew-20260822/report.md` records relay `v0.4.0` with the current app/extension; all 16 pairing, auth, room, reconnect, and owner-channel tests passed in 67 seconds and redaction canaries passed. There was no hang or corrupt/malformed projection.
- Precise hard-cutover limitation: the required previous tag (`v0.4.0`) postdates both relay-relevant hard cutovers (v0.1 auth domain separation and required `to_room`), while owner-channel v0.3 is app ↔ extension and relay-opaque. The repository has no pre-v0.1 unified release tag, so a previous-tag relay drill cannot honestly produce the clean mixed-version rejection side. Current↔v0.4 compatibility success is the correct observed result; auth-domain legacy rejection remains covered by relay negative tests. This limitation does not block the story because the clock dimension was fully exercised and the version dimension completed with bounded evidence.
- Verification: both drill scripts exited 0; `python3 -m unittest e2e.test_live_soak` passed 14 tests; triage selftest passed; `bash -n` passed; merged Compose config validated; `git diff --check` passed. No Dart source changed, so Flutter analyze was not required. `shellcheck` is unavailable on the VM.
- Simplification/discrepancies: one generic derived-image Dockerfile serves both glibc containers; production Dockerfiles remain dependency-free. Corrected this item's scalar `depends_on` to the substrate's required sequence shape. No new findings were parked.
