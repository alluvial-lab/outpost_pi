# Pattern: Atomic Snapshot Store with Marker-Last Migration

## Rationale

Local state needs two different durability boundaries: normal mutations must
replace a complete snapshot atomically, while a legacy migration must not claim
completion until every destination export has finished. Write snapshots through
a same-directory flushed temporary file and atomic rename. During migration,
write each independent destination first, preserve the source as recovery
evidence, and write the idempotence marker last. A missing marker therefore
means the migration can safely replay.

## When to use

Use for file-backed local state and one-shot format migrations:

1. Normalize and encode a complete versioned envelope before persistence.
2. Flush a same-directory temporary file, then rename it over the destination;
   serialize revisions so an older snapshot cannot win.
3. Export independent legacy stores separately and preserve their sources.
4. Write the completion marker only after all destinations have been attempted;
   an existing marker skips the migration and a missing marker replays it.

## When not to use

Do not write directly over a live JSON file, delete legacy sources before the
new state is committed, or use a marker written before destination exports.
Do not use marker-last migration as a substitute for a pending transition latch
when the transition is destructive and must gate access before cleanup begins.

## Examples

### Complete snapshots use flush plus same-directory rename

**File:** `cockpit/lib/app/core/data/storage/json_state_store.dart:306-332`

```dart
static Future<void> writeAtomic(File file, String contents) async {
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.tmp');
  final output = await temporary.open(mode: FileMode.write);
  try {
    await output.writeFrom(utf8.encode(contents));
    await output.flush();
  } finally {
    await output.close();
  }
  // bounded rename retries; return only after the destination is replaced
  await temporary.rename(file.path);
}
```

The real implementation retries transient rename failures; the invariant is
that callers see either the old complete file or the new complete file, never a
partially written destination.

### Revisions serialize writes and keep the newest snapshot authoritative

**File:** `cockpit/lib/app/core/data/storage/json_state_store.dart:190-214`

```dart
final revision = _revision;
final contents = encodeEnvelope(_data);
final previous = _writeTail;
final attempt = () async {
  try {
    await previous;
  } catch (_) {
    // A failed older snapshot must not poison newer persistence attempts.
  }
  await _atomicWriter(_file, contents);
  if (revision > _persistedRevision) _persistedRevision = revision;
}();
_writeTail = attempt;
```

A later complete snapshot waits behind an earlier attempt, but an earlier
failure cannot prevent the newest revision from being retried and committed.

### Legacy exports precede the completion marker

**File:** `cockpit/lib/app/core/data/storage/legacy_hive_migrator.dart:72-118`

```dart
for (final String storeName in storeNames) {
  // export or isolate this destination independently
  await JsonStateStore.writeAtomic(
    File(p.join(stateDirectory, '$storeName.json')),
    contents,
  );
}

await JsonStateStore.writeAtomic(
  marker,
  jsonEncode(<String, Object?>{
    'version': _markerVersion,
    'source': sourceDirectory == null ? 'none' : 'legacy_hive',
    'failedStores': failedStores,
  }),
);
```

The marker is the idempotence commit, not progress state. Existing markers skip
Hive and JSON rewrites; a marker-less interrupted run re-exports from the
preserved source.

### Tests prove replay and source preservation

**File:** `cockpit/test/core/data/legacy_hive_migrator_test.dart:85-124,159-176`

```dart
final result = await migrator().runIfNeeded();
expect(result.ran, isTrue);
for (final String name in LegacyHiveMigrator.storeNames) {
  expect(File(p.join(legacyDirectory, '$name.hive')).existsSync(), isTrue);
}
// deleting the marker and corrupting one destination must replay from Hive
```

The file-backed tests verify all destinations, preserved source files, and a
marker-less interrupted run rather than treating marker presence alone as
proof of migrated data.

## Common violations

- Writing the completion marker before the last destination write.
- Replacing the destination with `writeAsString` and exposing a truncated JSON
  file after a crash.
- Deleting legacy state after one successful export while another store remains
  uncommitted.
- Treating a failed destination as permission to mark the whole migration
  complete without recording the failed store.

## Related

- `durable-transition-latches.md` — marker-first pending latches gate a
  destructive transition; this pattern's marker-last record commits a finished
  migration.
- `canonical-projection-equivalence-oracle.md` — compare migrated state with
  the canonical projection after replay.

## Index entry

- **atomic-snapshot-store-marker-last-migration**: Flush complete snapshots through temp-and-rename, and write a migration completion marker only after all destinations finish.
