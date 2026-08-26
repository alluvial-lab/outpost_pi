---
id: feature-cockpit-storage-json-vs-hive
kind: feature
stage: implementing
tags: [cockpit]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Cockpit storage: evaluate JSON stores vs Hive (upstream 0802539b)

## Brief

Formed by groom 2026-08-26 from `backlog-cockpit-hive-json-store-migration`
(body retained in `.work/archive/`). Operator direction 2026-08-26: **defer
to upstream and evaluate in a vacuum** — the operator does not use the
cockpit yet, so there is no local-corruption pressure; decide on merits, not
on a promote trigger. The original item's "promote on first unrecoverable
corruption / before public Windows builds" gating is lifted by this
promotion.

## Context

Upstream `0802539b` replaced Hive with atomic JSON stores to fix Windows
crash classes (locked boxes, OneDrive-location corruption, dirty-shutdown
damage). Ours opens Hive synchronously at `cockpit/lib/main.dart:21-63` with
Hive repositories throughout. Their `json_state_store.dart` (tolerant read,
atomic write) is the workable target design.

## Work

1. Evaluate adopt-migrate-upstream-wholesale vs keep-Hive (with the bounded
   open-retry bandage from `story-harvest-cockpit-crash-class-ports` already
   landed) — operator leans upstream when the delta is reasonable.
2. If migrating: port `json_state_store` semantics, migrate persisted state,
   keep repository seams so the store swap stays behind one boundary.
3. Coordinate with `story-identity-boot-restore-race` if identity storage is
   touched — same-storage overlap.

Independent and NOT gated on this evaluation:
`gate-review-cockpit-bootstrap-wiring-test` (standalone story) lands the
bootstrap wiring test now — its retry/error-widget boundary is store-agnostic
and must hold under either backend.

## Grounding

The provenance remote was fetched successfully after the abbreviated direct
fetch was rejected, and commit `0802539b75d4f9ad404f15dada2cb735fb41e5d0`
was inspected. Its relevant design is a versioned, in-memory JSON key/value
store with tolerant reads, debounced temp-file + flush + rename writes, bounded
rename retry, a process-exit flush, Windows state under Application Support
rather than Documents/OneDrive, and a one-shot Hive-to-JSON exporter whose
marker is written last. This design adapts that storage slice to Outpost-Pi's
smaller current surface (four boxes, no realms/custom storage/terminal
scrollback) rather than importing unrelated upstream cockpit features.

Direct reading was sufficient: the local persistence surface is bounded to
`main.dart`, four Hive adapters, `cockpit_module.dart`, and their domain ports.
No exploratory fanout was needed. Independent design-time advisory review was
not available in this worker harness; implementation still receives the
caller's standard fresh-context review.

## Design decisions

- **Adopt or keep Hive**: Adopt atomic JSON stores. The retry bandage only masks
  short-lived locks; it cannot remove Hive's persistent lock files,
  append-oriented dirty-shutdown exposure, or Windows Documents/OneDrive
  placement. The upstream change is proven and the local delta is bounded.
- **Storage boundary**: Add one core `StateStore`/`StateStoreFactory` port and
  keep all feature/domain callers on their existing repositories. Concrete JSON
  and legacy Hive knowledge remains in data/setup adapters and composition.
- **Migration failure posture**: Migrate each known box independently, preserve
  every `.hive` file, record failed boxes in a marker written last, and start a
  failed/corrupt store empty rather than reviving the boot-crash class. The
  marker and diagnostics retain recovery evidence; migration never deletes the
  source.
- **Hive dependency removal**: Remove Hive from normal startup, repositories,
  and feature composition, and remove `hive_flutter`. Retain the core `hive`
  package only inside the one-shot legacy reader while installed user state
  remains a compatibility obligation; complete package removal is unsafe in
  the same release as the migration.
- **Identity overlap**: No identity store is touched. Cockpit state contains
  preferences, window bounds, projects, layouts, and dismissed-update state;
  `story-identity-boot-restore-race` concerns the mobile app's secure Owner
  identity. Record the non-overlap but add no dependency.
- **Independent bootstrap test**: Do not depend on
  `gate-review-cockpit-bootstrap-wiring-test`. The implementation must preserve
  its store-agnostic bootstrap-error boundary if that story lands concurrently.
- **UI surface**: None. This is a persistence/backend change, so no mockup
  fallback applies.

## Architectural choice

### Option A — keep Hive plus bounded open retry

This is the smallest patch and preserves all current adapters. It only helps a
transient startup lock, however, and leaves the demonstrated Windows failure
mechanisms and OneDrive-prone placement intact. It optimizes immediate diff size
at the cost of retaining the risky subsystem.

### Option B — shared state-store port plus atomic JSON adapters (chosen)

Port the upstream storage semantics behind a narrow core key/value port, adapt
each existing repository, and run a one-shot legacy exporter before opening JSON
state. It removes Hive from the live runtime, keeps domain and UI contracts
unchanged, and makes migration/atomicity independently testable. It costs a
bounded migration and lifecycle-flush path, but directly addresses the known
failure classes without importing upstream's unrelated current architecture.

### Option C — replace Hive with SQLite

SQLite provides transactional durability and mature locking, but these four
small, whole-document stores do not need queries or relational constraints. It
adds schema/migration machinery and native packaging surface without a product
benefit over atomic files.

Choose Option B. It follows upstream evidence, preserves Outpost-Pi's
ports/adapters architecture, and eliminates rather than bandages the failing
runtime.

## Trickiest unit first: legacy state migration

The highest-risk unit is the one-way conversion of real persisted state. It must
find the exact legacy debug/production Hive location, normalize dynamic Hive
maps into JSON-safe string-keyed data, tolerate one corrupt box without losing
other boxes, write each destination atomically, and commit only by writing the
migration marker last. Source boxes remain untouched as rollback evidence.

## Implementation Units

### Unit 1: Define the state-store port and atomic JSON adapter

**Files**:
- `cockpit/lib/app/core/domain/contracts/state_store.dart`
- `cockpit/lib/app/core/data/storage/json_state_store.dart`
- `cockpit/test/core/data/json_state_store_test.dart`

**Story**: `feature-cockpit-storage-json-vs-hive-storage-port-json-store`

```dart
abstract interface class StateStore {
  Object? get(String key);
  Iterable<String> get keys;
  Iterable<Object?> get values;
  Future<void> put(String key, Object? value);
  Future<void> putAll(Map<String, Object?> entries);
  Future<void> delete(String key);
  Future<void> flush();
}

abstract interface class StateStoreFactory {
  Future<StateStore> open(String name);
  Future<void> flushAll();
}

final class JsonStateStoreFactory implements StateStoreFactory {
  JsonStateStoreFactory(this.rootDirectory);
  final String rootDirectory;

  @override
  Future<StateStore> open(String name);

  @override
  Future<void> flushAll();
}

final class JsonStateStore implements StateStore {
  static const int formatVersion = 1;
  static const Duration debounceWindow = Duration(milliseconds: 150);

  static Future<void> writeAtomic(File file, String contents);
}
```

**Implementation Notes**:
- The factory owns the per-absolute-path instance cache and flush lifecycle;
  repositories never access a static/global backend.
- Disk shape is `{"version":1,"data":{...}}`. Missing, empty, malformed, or
  unknown-version/envelope files load as empty and emit only content-free
  diagnostics; no bad payload or user path is logged.
- Mutations update memory synchronously, coalesce in a 150 ms window, serialize
  commits per store, and return a `Future` for the corresponding attempted
  commit. Atomic writes create the parent, write and flush a same-directory
  `.tmp`, then rename with bounded filesystem retry.
- `flushAll()` drains every pending store on requested app exit. Tests inject a
  temporary root; no singleton-reset API is needed.

**Acceptance Criteria**:
- [ ] Round-trip, idempotent open, delete, debounce/coalescing, and multi-store
      flush behavior are covered at the stable port boundary.
- [ ] Corrupt/unsupported/absent files open empty and remain writable without
      failing bootstrap.
- [ ] Replacing an existing file leaves a valid complete envelope and no stale
      temp file on success.
- [ ] Concurrent mutations serialize without an older snapshot overwriting a
      newer one.

### Unit 2: Add storage paths and one-shot Hive export

**Files**:
- `cockpit/lib/app/core/data/storage/storage_paths.dart`
- `cockpit/lib/app/core/data/storage/legacy_hive_migrator.dart`
- `cockpit/test/core/data/storage_paths_test.dart`
- `cockpit/test/core/data/legacy_hive_migrator_test.dart`

**Story**: `feature-cockpit-storage-json-vs-hive-legacy-migration`

```dart
final class CockpitStoragePaths {
  const CockpitStoragePaths._();

  static Future<String> stateDirectory();
  static Future<List<String>> legacyHiveDirectories();
  static String dataDirectoryUnder(String root, [p.Context? context]);
}

final class LegacyHiveMigrator {
  const LegacyHiveMigrator({
    required this.stateDirectory,
    required this.legacyDirectories,
  });

  static const List<String> storeNames = <String>[
    'settings',
    'window_state',
    'projects',
    'layouts',
  ];

  Future<LegacyMigrationResult> runIfNeeded();
}

final class LegacyMigrationResult {
  const LegacyMigrationResult({
    required this.ran,
    required this.failedStores,
  });
  final bool ran;
  final List<String> failedStores;
}
```

**Implementation Notes**:
- Keep debug/production separation (`cockpit-debug`/`cockpit`). JSON defaults to
  Application Support on Windows to avoid KFM/OneDrive; macOS/Linux retain the
  current Documents root. Build all paths with `package:path`.
- Search legacy candidates in deterministic order, including the current
  Documents location and Application Support. The first directory containing a
  known `.hive` box is the source.
- Normalize nested `Map<dynamic, dynamic>` keys recursively before JSON encode.
  Export stores independently with bounded lock retry. A failed store gets an
  empty JSON envelope and a diagnostic/category entry, while successful stores
  remain preserved.
- Write `migration.json` last as the idempotence commit. Preserve all Hive files;
  fresh installs write a no-source marker and create state files lazily.

**Acceptance Criteria**:
- [ ] Representative values for all four local boxes survive migration exactly,
      including nested maps and the layout's encoded JSON string.
- [ ] Migration is idempotent and does not overwrite JSON after the marker.
- [ ] A failed/corrupt box is isolated and recorded while other boxes migrate.
- [ ] Source Hive files are never deleted, and an interrupted run without the
      marker can safely rerun.
- [ ] Windows path tests prove Application Support placement and native
      separator normalization without requiring a Windows host.

### Unit 3: Replace every repository adapter without changing domain contracts

**Files**:
- `cockpit/lib/app/core/data/repositories/json_settings_store.dart`
- `cockpit/lib/app/cockpit/data/repositories/json_project_repository.dart`
- `cockpit/lib/app/cockpit/data/repositories/json_workspace_layout_store.dart`
- `cockpit/lib/app/cockpit/data/repositories/json_dismissed_update_store.dart`
- `cockpit/test/core/data/json_repository_adapters_test.dart`
- `cockpit/lib/app/core/domain/contracts/settings_store.dart`
- `cockpit/lib/app/cockpit/domain/contracts/project_repository.dart`
- `cockpit/lib/app/cockpit/domain/contracts/workspace_layout_store.dart`
- `cockpit/lib/app/cockpit/domain/contracts/dismissed_update_store.dart`

**Story**: `feature-cockpit-storage-json-vs-hive-repository-adapters`

```dart
final class JsonSettingsStore implements SettingsStore {
  JsonSettingsStore(this._store);
  static const String storeName = 'settings';
  final StateStore _store;
}

final class JsonProjectRepository implements ProjectRepository {
  JsonProjectRepository(this._store);
  static const String storeName = 'projects';
  final StateStore _store;
}

final class JsonWorkspaceLayoutStore implements WorkspaceLayoutStore {
  JsonWorkspaceLayoutStore(this._store);
  static const String storeName = 'layouts';
  final StateStore _store;
}

final class JsonDismissedUpdateStore implements DismissedUpdateStore {
  JsonDismissedUpdateStore(this._store);
  final StateStore _store;
}
```

**Implementation Notes**:
- Preserve repository public signatures, key names, primitive map shapes,
  project ordering/defaults, and corrupt-layout-as-missing behavior. This is a
  backend swap, not a domain schema redesign.
- Repository tests use an in-memory `StateStore` fake so semantics are proven
  independently of file mechanics.
- Rewrite backend-specific domain comments to describe persistence contracts,
  not Hive or JSON implementations.

**Acceptance Criteria**:
- [ ] Settings, projects, last-selection, layouts, and dismissed-version
      semantics match the current adapters.
- [ ] No domain or UI file imports a concrete JSON/Hive adapter.
- [ ] Malformed project records are ignored and malformed layout strings return
      `null`, preserving current recovery behavior.

### Unit 4: Cut bootstrap/composition over and retire live Hive

**Files**:
- `cockpit/lib/main.dart`
- `cockpit/lib/app/app_module.dart`
- `cockpit/lib/app/cockpit/cockpit_module.dart`
- `cockpit/pubspec.yaml`
- `cockpit/pubspec.lock`
- `cockpit/test/domain/crash_recovery_test.dart`
- `cockpit/CLAUDE.md`
- `.agents/skills/flutter-desktop-cockpit/SKILL.md`
- `docs/ARCHITECTURE.md`
- `docs/SPEC.md`

**Deletes**:
- `cockpit/lib/app/core/data/hive_box_opener.dart`
- `cockpit/lib/app/core/data/repositories/hive_settings_store.dart`
- `cockpit/lib/app/cockpit/data/repositories/hive_project_repository.dart`
- `cockpit/lib/app/cockpit/data/repositories/hive_workspace_layout_store.dart`
- `cockpit/lib/app/cockpit/data/repositories/hive_dismissed_update_store.dart`

**Story**: `feature-cockpit-storage-json-vs-hive-remove-hive-runtime`

```dart
Future<Module> buildAppModule({
  required PiSpawnConfig config,
  required StateStoreFactory stateStores,
});

Future<Module> buildCockpitModule(StateStoreFactory stateStores);
```

**Implementation Notes**:
- `main()` resolves paths, runs legacy migration before any JSON open, constructs
  one `JsonStateStoreFactory`, loads settings/window state, then passes the
  factory through the composition root. `cockpit_module.dart` opens named stores
  only through that port and binds JSON repositories.
- Add an app-exit lifecycle owner that awaits `stateStores.flushAll()`; keep the
  existing 400 ms window-resize debounce and persist through `StateStore`.
- Remove `Hive.initFlutter`, all live box opening/retry, `hive_flutter`, and the
  obsolete Hive retry tests. Keep `hive` only for
  `legacy_hive_migrator.dart`; add direct `path` and `path_provider`
  dependencies used by production code.
- Preserve the bootstrap exception-to-`BootstrapErrorApp` boundary. If
  `gate-review-cockpit-bootstrap-wiring-test` lands concurrently, adapt rather
  than delete its storage-neutral assertion; do not introduce a substrate
  dependency.
- Roll durable docs forward from Cockpit/Hive claims to atomic JSON plus the
  isolated legacy migration reader.

**Acceptance Criteria**:
- [ ] Normal application startup and feature composition contain no Hive API,
      boxes, or lock retry; the only `package:hive` import is the legacy
      migrator.
- [ ] Settings load before first frame, window bounds restore/persist, and all
      cockpit repositories resolve through the single factory boundary.
- [ ] Requested app exit flushes pending state; bootstrap failures still render
      `BootstrapErrorApp` rather than escaping.
- [ ] `flutter analyze` and `flutter test` pass from `cockpit/` using the
      repository toolchain; no generated/cache artifacts are committed.
- [ ] Durable Cockpit architecture/reference prose describes current JSON
      persistence and no longer instructs agents to open Hive boxes.

## Implementation Order

1. `feature-cockpit-storage-json-vs-hive-storage-port-json-store`
2. In parallel after the port: legacy migration/paths and repository adapters
3. `feature-cockpit-storage-json-vs-hive-remove-hive-runtime` after both branches
4. Run Cockpit analyze/tests and the standard feature-level fresh-context review

## Simplification

- Delete five Hive runtime adapters/helpers and their implementation-bound retry
  tests instead of carrying parallel backends.
- Keep existing domain repository contracts; do not create JSON-shaped domain
  models or expose key/value storage to UI/ViewModels.
- Do not import upstream custom storage location, realms, database, task, or
  scrollback features absent from this fork.
- Retaining `hive` only as a one-shot legacy reader is the minimum earned
  compatibility cost for real persisted user state; it is not a second live
  backend.

## Testing

- **State-store interface/regression tests** protect tolerant boot, atomic
  replacement, serialized/debounced writes, and exit flush—the failure classes
  motivating the swap.
- **Migration tests** protect real user data, idempotence, partial corruption,
  source preservation, and marker-last interruption recovery.
- **Repository adapter tests** protect stable domain behavior independently of
  the file implementation.
- **Composition/bootstrap evidence** is `flutter analyze`, the full Cockpit test
  suite, and preservation of the independent storage-neutral bootstrap wiring
  test when present.
- Remove only Hive-specific retry tests that become impossible and valueless;
  retain the terminal crash-recovery and bootstrap-error assertions.

## Risks

- **Migration silently drops one store**: isolate per-store failure, record it
  in the marker/diagnostics, preserve source boxes, and test partial migration.
  Re-pairing is not involved because identity is outside this surface.
- **Debounced writes die during process termination**: own `flushAll()` at the
  requested-exit lifecycle boundary. Hard kills can still lose at most the
  current debounce window, but cannot leave a half-written destination.
- **Atomic rename differs across desktop platforms**: use a same-directory temp
  file, bounded filesystem retries, and a real Windows smoke before claiming
  Windows validation. Unit tests prove the platform-neutral contract only.
- **Corrupt JSON appears as defaults**: this is intentional availability-first
  behavior inherited from upstream; content-free diagnostics and preserved Hive
  migration sources provide recovery evidence without making boot fatal.
- **Legacy Hive package lingers**: confine it to one migration file and document
  the revisit condition (remove only after the installed migration window is
  deliberately closed).
