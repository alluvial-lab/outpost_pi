---
id: idea-live-runner-adb-lock-fd-leak
created: 2026-08-22
updated: 2026-08-22
tags: [e2e, bug]
---

`e2e/run-live.sh` opens the emulator lane flock on a shell file descriptor, then
starts the adb server while that descriptor is inheritable. After a successful
live run and emulator shutdown, the adb daemon retained the lock fd even though
no `run-live.sh`, emulator, or Flutter process remained; the next run refused
the lane as owned. `adb kill-server` released it. Keep the lane-lock descriptor
out of child processes (or otherwise close it before starting adb) so normal
runner cleanup leaves the lane reusable without killing the global adb server.
