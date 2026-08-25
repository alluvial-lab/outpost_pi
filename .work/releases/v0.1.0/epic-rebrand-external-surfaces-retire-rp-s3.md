---
id: epic-rebrand-external-surfaces-retire-rp-s3
kind: feature
stage: done
tags: [rebrand, app, cockpit, rp-s3]
parent: epic-rebrand-external-surfaces
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
---

# Retire rp-s3 download server

## Brief

rp-s3 is a download/update server that served auto-update manifests
(`latest.json`) for the cockpit (desktop app) and the phone app, hosted at
`rp-s3.jacobmoura.work` on Jacob Moura's VPS (`rp-s3/docker-compose.yml`
mounts `/Users/flutterando/...` host paths). The operator has not run the
cockpit and is not exercising the phone-app update path; the host is
third-party infrastructure being retired.

This feature stops product code from pointing at the dead host. The
`UpdateCheckerImpl` auto-update code is NOT deleted (it's a working feature
that can return when distribution stands up) — its manifest URL stops
pointing at `rp-s3.jacobmoura.work`. The checker already silently returns
`null` on any network failure, so a non-resolving host is equivalent to "no
update available."

## Epic context
- Parent epic: `epic-rebrand-external-surfaces`
- Position in epic: independent mechanical feature; runs in parallel with F1
  (no-default relay) and F2 (hostname migration). Owns the
  `rp-s3.jacobmoura.work` hostname only.

## Foundation references
- `cockpit/lib/app/cockpit/data/update/update_checker_impl.dart` —
  `defaultManifestUrl = 'https://rp-s3.jacobmoura.work/downloads/cockpit/latest.json'`
- `app/lib/data/update/update_checker_impl.dart` —
  `defaultManifestUrl = 'https://rp-s3.jacobmoura.work/downloads/app/latest.json'`
- `rp-s3/docker-compose.yml` — `image: jacobmoura7/rp-s3:latest` (missed in
  commit `1c8cad8`) + `rp-s3.jacobmoura.work` URL comment + `/Users/flutterando/...` host paths
- `rp-s3/README.md`, `rp-s3/build-docker.sh` — update docs to "not currently deployed"
- `cockpit/packaging/README.md` — appcast URLs
  (`rp-s3.jacobmoura.work/.../appcast-{macos,windows}.xml`)
- `site/src/lib/cockpit-release.ts`, `site/src/lib/app-release.ts` — release
  asset URLs that may point at rp-s3 or `outpost-pi.jacobmoura.work`
  (coordinate with F2 on the `outpost-pi` ones)

## Design decisions
- **Remove the runtime default rather than use a sentinel.** `UpdateCheckerImpl`
  accepts an optional injected manifest URL, but its normal construction has no
  URL and returns `null` before creating a request. This makes "distribution is
  disabled" explicit, avoids an arbitrary network/DNS dependency and a 5-second
  timeout on each check, and preserves an intentional re-enablement seam: a
  future distribution composition root can inject a verified URL.
- **Disable both cockpit update paths.** The cockpit's manual `latest.json`
  checker and its native Sparkle/WinSparkle appcast feed are distinct consumers;
  leaving `_kDownloadsBase` would retain a fetch to the retired host. Normal
  platform targets therefore have no `selfUpdateFeedUrl`, so
  `_buildSelfUpdater` selects `NoopSelfUpdater`.
- **Site defaults are absent, not sentinels.** `APP_MANIFEST_URL` and
  `MANIFEST_URL` remain environment override points, but have no rp-s3 fallback.
  When absent, their loaders return the bundled mock without calling `fetch`.
- **Keep `rp-s3/` dormant and portable.** It remains a usable Rust/axum server,
  but its README and build script state it is not currently deployed. Compose
  uses the fork-local `outpost-pi-rp-s3:latest` image and configurable local
  data-directory defaults instead of Jacob's VPS paths. No deployment or DNS
  replacement is introduced.
- **F2 owns only `outpost-pi.jacobmoura.work`.** This feature changes only
  rp-s3 strings in the shared site release modules; it must not edit F2's mock
  artifact URLs. The source scope is bounded and already mapped locally, so no
  exploratory-agent fan-out or advisory review was warranted.

## Architectural choice

Three viable approaches were considered:

1. **Non-resolving sentinel URL.** Change the hostname to an invalid reserved
   address and rely on the existing catches. It is a small textual edit, but it
   keeps a network side effect, delays update checks by the configured timeout,
   and obscures that distribution is deliberately disabled.
2. **Remove default URLs while retaining optional injection (chosen).** Model
   distribution as absent in the default composition; `fetchLatest()` is an
   immediate no-op without a URL. This is explicit, avoids dead-network work,
   and leaves the adapter and its injectable integration seam intact.
3. **Delete update and rp-s3 code.** This eliminates references but needlessly
   discards a working, bounded distribution capability that the operator may
   restore later.

Approach 2 best matches the operator decision to retire third-party hosting
without abandoning the feature.

## Implementation Units

### Unit 1: Default update paths no-op
**Files**:
- `app/lib/data/update/update_checker_impl.dart`
- `cockpit/lib/app/cockpit/data/update/update_checker_impl.dart`
- `cockpit/lib/app/cockpit/cockpit_module.dart`
- new focused tests beneath `app/test/data/update/` and
  `cockpit/test/app/cockpit/data/update/` where the existing test layout permits

**Story**: `epic-rebrand-external-surfaces-retire-rp-s3-runtime-update-noop`

```dart
// app/lib/data/update/update_checker_impl.dart
class UpdateCheckerImpl implements UpdateChecker {
  UpdateCheckerImpl({String? manifestUrl, Duration timeout = ..., Dio? dio})
      : manifestUrl = manifestUrl,
        _dio = dio ?? _defaultDio(timeout);

  final String? manifestUrl;

  Future<UpdateInfo?> fetchLatest() async {
    final manifestUrl = this.manifestUrl;
    if (manifestUrl == null) return null;
    // Existing HTTP/status/body/schema handling stays unchanged.
  }
}

// cockpit/lib/app/cockpit/data/update/update_checker_impl.dart
class UpdateCheckerImpl implements UpdateChecker {
  const UpdateCheckerImpl({this.manifestUrl, this.timeout = ...});

  final String? manifestUrl;

  Future<UpdateInfo?> fetchLatest() async {
    final manifestUrl = this.manifestUrl;
    if (manifestUrl == null) return null;
    // Existing HttpClient lifecycle and parsing remain unchanged.
  }
}
```

**Implementation notes**:
- Remove both `defaultManifestUrl` constants; do not substitute a fake URL.
- Preserve the public constructor override for a future explicit distribution
  composition and preserve all error-to-`null` handling for that injected URL.
- Remove `_kDownloadsBase`; make macOS and Windows `UpdateTarget`s omit
  `selfUpdateFeedUrl`. `_buildSelfUpdater` already maps a missing feed to
  `NoopSelfUpdater`, so no new abstraction is necessary.
- Update `cockpit/packaging/README.md` to state appcasts are not currently
  published/deployed and must be configured again with distribution, rather
  than directing an operator to rp-s3.

**Acceptance Criteria**:
- [ ] Default app and cockpit `UpdateCheckerImpl().fetchLatest()` return `null`
  without issuing an HTTP request.
- [ ] An explicitly supplied manifest URL retains the current HTTP parsing and
  silent-failure behavior.
- [ ] Cockpit macOS/Windows native self-update gets `NoopSelfUpdater`; no
  runtime update URL contains `rp-s3.jacobmoura.work`.
- [ ] Focused tests cover the default no-op path; `flutter analyze` passes in
  both touched Flutter projects.

---

### Unit 2: Site release loaders have no live default
**Files**:
- `site/src/lib/app-release.ts`
- `site/src/lib/cockpit-release.ts`

**Story**: `epic-rebrand-external-surfaces-retire-rp-s3-site-manifest-fallback`

```ts
export const APP_MANIFEST_URL = process.env.NEXT_PUBLIC_APP_MANIFEST_URL;
export const MANIFEST_URL = process.env.NEXT_PUBLIC_COCKPIT_MANIFEST_URL;

export async function loadAppManifest(): Promise<AppManifestLoad> {
  if (!APP_MANIFEST_URL) {
    return { manifest: APP_MOCK_MANIFEST, live: false };
  }
  // Existing fetch, validation, and fallback handling.
}
```

`loadCockpitManifest()` follows the same absence guard before its existing
fetch/validation path.

**Implementation notes**:
- Update the module comments to describe optional operator-provided manifests,
  not a future rp-s3/VPS deployment.
- Do not touch mock artifact URLs containing
  `outpost-pi.jacobmoura.work`; F2 owns that hostname migration. Coordinate
  mechanically by retaining their exact lines.

**Acceptance Criteria**:
- [ ] With no public manifest environment variable, neither loader calls
  `fetch` and each returns its existing mock with `live: false`.
- [ ] An explicit environment URL still takes the existing fetch/shape-validation
  path and falls back to the mock on failure.
- [ ] Neither module retains an rp-s3 URL or language promising the retired VPS.

---

### Unit 3: Dormant rp-s3 operational documentation
**Files**:
- `rp-s3/docker-compose.yml`
- `rp-s3/README.md`
- `rp-s3/build-docker.sh`

**Story**: `epic-rebrand-external-surfaces-retire-rp-s3-dormant-server-docs`

```yaml
services:
  rp-s3:
    build: .
    image: outpost-pi-rp-s3:latest
    volumes:
      - ${RP_S3_COCKPIT_DATA_DIR:-./data/cockpit}:/data/cockpit:ro
      - ${RP_S3_APP_DATA_DIR:-./data/app}:/data/app:ro
```

**Implementation notes**:
- Lead the README with the current state: rp-s3 is dormant and not currently
  deployed by Outpost-Pi. Retain its routes/configuration as a future
  self-hosted-distribution reference, without Jacob's hostname, VPS, or paths.
- Describe local compose usage as an operator-initiated future deployment,
  including the named data-directory environment variables; do not claim a
  running public endpoint.
- Retain `build-docker.sh` as a local image builder, but state/emit that a
  successful build does not deploy the server. Its local image name remains
  `outpost-pi-rp-s3`.

**Acceptance Criteria**:
- [ ] Compose no longer uses `jacobmoura7/rp-s3:latest` or
  `/Users/flutterando` paths.
- [ ] README and build script accurately say the service is not currently
  deployed and contain no retired rp-s3 hostname.
- [ ] `docker compose config` validates when Docker Compose is available;
  otherwise the implementation notes the unavailable prerequisite.

---

### Unit 4: Cross-surface retirement verification
**Files**: no primary production file; verifies Units 1–3 and makes only
necessary corrections within their owned scope.

**Story**: `epic-rebrand-external-surfaces-retire-rp-s3-cross-surface-verification`

**Implementation notes**:
- Run a tracked-source grep for `rp-s3.jacobmoura.work`,
  `jacobmoura7/rp-s3`, and `/Users/flutterando`; do not let ignored/generated
  `site/.next/` artifacts create false failures.
- Re-run Flutter analyzer checks after the completed runtime story. Run
  relevant site static checks if available.
- Verify the shared site files still retain F2-owned
  `outpost-pi.jacobmoura.work` lines untouched; report that intentional
  handoff rather than changing it.

**Acceptance Criteria**:
- [ ] No tracked product-source reference remains to the retired rp-s3 host,
  image namespace, or Jacob VPS paths.
- [ ] The app and cockpit analyzers pass, or any environmental prerequisite is
  recorded exactly.
- [ ] The verification story does not absorb F2's hostname migration.

## Implementation Order

1. In parallel, implement `runtime-update-noop`, `site-manifest-fallback`, and
   `dormant-server-docs`; their write sets do not overlap except that the first
   is responsible for cockpit packaging documentation.
2. Run `cross-surface-verification` after all three prerequisite stories
   complete. It is the only dependency join, making the retirement assertion
   explicit without inventing dependencies between independent edits.

## Testing

### Runtime update adapters
- Add focused default-construction tests for both adapters: no URL yields
  `null` immediately. Preserve or add a small injected-URL fixture/server test
  for successful parsing and an invalid-response/null case where practical.
- `flutter analyze` from `app/` and `cockpit/`; run their focused/full test
  suites during implementation as dependencies permit.

### Site loaders
- If the site has a local test runner for these modules, assert absence guards
  return the mock without a fetch and explicit URLs retain validation. At
  minimum, run the repository's site lint/type/build check appropriate to the
  installed dependencies.

### Dormant compose/docs
- Validate Compose interpolation through `docker compose config` when Docker
  is installed. Use tracked-file grep as the durable check that third-party
  paths and hostnames are gone.

## Risks

- **Missed desktop self-update feed**: changing only `UpdateCheckerImpl` would
  leave Sparkle/WinSparkle fetching the rp-s3 appcasts. Unit 1 explicitly
  removes `_kDownloadsBase` and relies on the existing `NoopSelfUpdater` path.
- **Accidental F2 interference**: both features edit the same site modules.
  This feature must make only rp-s3/default-manifest changes and leave every
  `outpost-pi.jacobmoura.work` mock artifact line for F2.
- **Future distribution ambiguity**: removing defaults means a new deployment
  must deliberately inject/configure URLs. That is intentional; the optional
  constructors and environment overrides are the documented re-enablement
  seam.
- **Verification noise**: `site/.next/` is generated/ignored and can preserve
  stale URLs locally. Verify tracked source rather than generated output.

## Design verification

- `flutter analyze` in `app/` passed with no issues after setting the
  repository-local writable `PUB_CACHE` required by this sandbox.
- `flutter analyze` in `cockpit/` passed with no issues using the same
  repository-local cache. Both initial plain-PATH runs correctly exposed the
  read-only default cache prerequisite; no source change was involved.

## Review (2026-07-15, standard, cross-model fresh-context)

Reviewer: `openai-codex/gpt-5.6-sol` (different model class from the umans
orchestrator). One balanced pass over the integrated feature diff
(`376fa38..HEAD`), focused on rp-s3 retirement (update-checker noop, site
manifest fallback, dormant-server docs).

### Findings
- None. rp-s3 retirement is coherent: default update checks perform no HTTP,
  optional injection remains, site loaders fall back safely, and dormant
  Compose configuration validates. Wire-stable identifiers unchanged.

### Verdict
Approve. Advanced `review → done`.
