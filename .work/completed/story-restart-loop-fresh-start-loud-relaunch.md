---
id: story-restart-loop-fresh-start-loud-relaunch
kind: story
completed: 2026-10-06
tags: [pi-extension, workflow, bug]
created: 2026-10-06
updated: 2026-10-06
---

# Restart-loop: explicit fresh-start path + loud, persistent relaunch trace

Completed (`d6f3b649b`, reviewed `53e97b431`). Folded `idea-restart-loop-fresh-start` and `backlog-restart-loop-silent-relaunch-failure`: added an explicit `--fresh-first` path to the Pi restart-loop wrapper so skill/package changes reach sessions without mobile `/new`, plus persistent lifecycle logging and `RELAUNCH-FAILED-FAST` failure traces so relaunch exits never disappear silently. Full pre-migration story record preserved in Git history at `fa32d6abb`.
