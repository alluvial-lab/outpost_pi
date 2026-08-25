---
id: backlog-cockpit-hive-json-store-migration
created: 2026-08-15
updated: 2026-08-15
tags: [cockpit, bug]
---

# Cockpit: migrate Hive → atomic JSON stores (Windows crash classes)

Upstream `0802539b`: replaced Hive with atomic JSON stores to fix Windows
crash classes (locked boxes, OneDrive-location corruption, dirty-shutdown
damage). Ours still opens Hive synchronously at `cockpit/lib/main.dart:42-51`
with Hive repositories throughout, so the corruption classes remain
structurally possible. Their `json_state_store.dart` (tolerant read,
atomic write) is a workable target design.

## Why parked, and promote trigger

**L** architecture migration, not a cherry-pick; no local corruption
reproduction (macOS daily use; bounded-retry bandage landing in
`story-harvest-cockpit-crash-class-ports` covers the transient half).
**Promote** on the first unrecoverable Hive corruption, or BEFORE shipping
public Windows builds (Windows is where the crash classes live). If the
identity-boot-restore work (see `story-identity-boot-restore-race`) touches
the same storage, coordinate designs first.
