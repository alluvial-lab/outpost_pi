---
id: backlog-app-debug-capture-buffer-retention
created: 2026-09-08
updated: 2026-09-08
tags: [app, bug, workflow]
---

# Debug capture buffer retention: 1 MiB ≈ 13 min under active streaming

Metronome-watch capture (2026-09-08) retained only 13 minutes despite weeks
since last clear: the byte-capped 1 MiB ring floods under current
instrumentation when multiple rooms stream (replayDedup per-event rows +
wsIn per-frame intents ≈ 6,700 of 7,304 events in one busy window). The
"covers ~48h" comment in debug_log_impl.dart assumes idle-rate events.

Tuning options (any one): aggregate replayDedup into count rows, sample
wsIn intents, or raise the cap. Cheap; directly gates how much evidence
the next flake capture retains.
