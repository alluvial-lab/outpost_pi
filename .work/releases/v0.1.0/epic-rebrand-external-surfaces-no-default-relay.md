---
id: epic-rebrand-external-surfaces-no-default-relay
kind: feature
stage: done
tags: [rebrand, pi-extension, app]
parent: epic-rebrand-external-surfaces
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
---

# Remove community relay default (no-default relay)

## Brief

Both clients hard-fallback to `kDefaultRelayUrl` (`relay-rp1.jacobmoura.work`,
Jacob Moura's infrastructure) when no explicit relay is configured. The
community relay is being retired from the product — Outpost-Pi becomes
local-relay-only. This feature removes the silent default and makes
"unconfigured" an actionable, surfaced state rather than a hidden fallback to
a dead third-party host.

This is the design-bearing slice of the epic: it changes onboarding UX, not
just constants. The "Community relay" card in onboarding must go, and
self-hosted relay selection becomes mandatory.

## Epic context
- Parent epic: `epic-rebrand-external-surfaces`
- Position in epic: the only UX-bearing feature; F2 (hostname migration) and
  F3 (rp-s3 retirement) are independent mechanical features that run in
  parallel. This feature owns the `relay-rp1.jacobmoura.work` hostname's
  removal; F2 owns `outpost-pi`/`remote-pi` hostnames; F3 owns `rp-s3`.

## Foundation references
- `pi-extension/src/config.ts` — `kDefaultRelayUrl`, `resolveRelayUrl()`
  precedence (env → config → default)
- `app/lib/data/transport/relay_config.dart` — mirror: `kDefaultRelayUrl`,
  `resolveRelayUrl(prefs)`
- `app/lib/ui/onboarding/widgets/relay_step.dart` — the "Community relay"
  card with `footer: kDefaultRelayUrl`
- `app/lib/ui/onboarding/viewmodels/onboarding_viewmodel.dart` —
  "empty = default" logic in relay validation
- `app/lib/ui/onboarding/states/onboarding_state.dart` — `RelayChoice` enum
  (`community`, `custom`)
- `app/lib/ui/settings/settings_page.dart` + `settings_viewmodel.dart` —
  settings relay field defaults to `kDefaultRelayUrl`
- `app/lib/pairing/pair_request_flow.dart`, `app/lib/config/dependencies.dart`,
  `app/lib/data/mesh/mesh_client.dart` — callers of `resolveRelayUrl`

## Design decisions (inherited from epic)
- **No default relay.** Empty/absent relay URL means "not configured." Both
  clients surface an actionable state ("set a relay via /outpost-pi
  set-relay" / onboarding forces selection) rather than silently falling
  back.

## What this feature does NOT cover
- Migrating the site/homepage hostname (`outpost-pi.jacobmoura.work`) —
  that's F2 (`epic-rebrand-external-surfaces-hostname-migration`).
- Retiring rp-s3 — that's F3 (`epic-rebrand-external-surfaces-retire-rp-s3`).

## Design decisions

- **Unconfigured representation**: `resolveRelayUrl` returns a discriminated
  resolution state, not a nullable string or a thrown error. TypeScript returns
  `{ url: null, source: "unconfigured" }`; the app returns the sealed
  `UnconfiguredRelay` case. This forces transport callers to handle absence at
  compile time while letting command/UI boundaries give a recovery action.
- **Error ownership**: configuration is surfaced at the first user-facing
  boundary: extension start/status names `/outpost-pi set-relay <url>`;
  app pairing and connection report Settings; mesh HTTP returns its existing
  typed failure result. A resolver must stay pure and never throw merely
  because configuration is absent.
- **Existing app installations**: do not reset pairing/onboarding persistence.
  A legacy `onboardingCompleted: true` plus absent `relayUrl` remains an
  explicit unconfigured state: Settings displays it, pairing stops before I/O,
  and the connection manager becomes non-retryable offline. This avoids a
  destructive migration while preventing a retry storm or dead-host timeout.
- **Onboarding shape**: remove `RelayChoice` entirely. There is one selected
  self-hosted URL form, so a blank URL disables Continue and submit reports the
  existing shared validation message; a valid URL is persisted before entering
  the pairing step.
- **UI fallback**: no mockup was created. This is a minor composition change to
  the existing onboarding/settings patterns (one card removed and an existing
  URL field made mandatory), with no new screen or journey. The parent epic has
  no mockup to inherit.
- **Dispatch**: direct-read mapping covered the bounded, known extension and
  app call sites. No exploratory fan-out was needed. The implementation splits
  by write ownership: extension and app resolution can run in parallel; the app
  UI story follows its app-resolution contract.

## Other agent review

- Invoked because: this is a cross-client configuration contract with an
  onboarding behavior change under autopilot.
- Phase 1 / Phase 2: skipped — this delegated harness exposes no selectable
  cross-model peer or worker-dispatch tool. The principles policy makes this
  advisory pass non-blocking; the completion review remains the autopilot
  owner's responsibility.

## Architectural choice

Three options were considered:

1. **Return `String?` / `string | null`**. This is small, but callers can
   reintroduce arbitrary null handling and lose the reason an URL is absent.
2. **Throw from `resolveRelayUrl`**. This fails fast, but turns a normal,
   recoverable first-run configuration state into exception-driven control flow
   and cannot render useful status/UI before catching.
3. **Return a discriminated resolution result** (chosen). A configured branch
   carries the canonical HTTP(S) URL and source; an unconfigured branch carries
   no URL and a named source/state. Each I/O boundary selects a deliberate
   recovery path. This is explicit, testable, and makes a later source addition
   compile-visible.

The two clients use their local idioms rather than a hand-maintained
cross-language wire contract: this is persisted local configuration, not a
protocol message. They preserve the common semantic invariant: no configured
source means no URL and no connection attempt.

## Implementation Units

### Unit 1: Extension relay resolution and command surfaces

**Files**: `pi-extension/src/config.ts`,
`pi-extension/src/config.test.ts`,
`pi-extension/src/index.ts`,
`pi-extension/src/extension/command_surface/pairing_coordinator.ts`,
`pi-extension/src/extension/command_surface/standalone_cli.ts`,
`pi-extension/src/mcp/mesh_server.ts`, `pi-extension/src/extension.test.ts`,
`pi-extension/test/ping.test.ts`, `pi-extension/CLAUDE.md`

**Story**: `epic-rebrand-external-surfaces-no-default-relay-extension-unconfigured-state`

```ts
export type ConfiguredRelayResolution = {
  readonly url: string;
  readonly source: "env" | "config";
};

export type UnconfiguredRelayResolution = {
  readonly url: null;
  readonly source: "unconfigured";
};

export type RelayResolution =
  | ConfiguredRelayResolution
  | UnconfiguredRelayResolution;

export function resolveRelayUrl(): RelayResolution;
```

**Implementation notes**:

- Preserve `OUTPOST_PI_RELAY` > persisted `config.json.relay` precedence and
  HTTP(S) canonicalization. Delete `kDefaultRelayUrl`; no source has a default
  URL.
- Start paths (`_startRelayViaTransport` and `PairingCoordinator.startRelay`)
  branch on `source === "unconfigured"` before identity/socket work and notify
  `Relay not configured. Run /outpost-pi set-relay <http(s) URL> and try again.`
  Only configured branches call `toWebSocketUrl` or save an active relay URL.
- Status renders a distinct off/unconfigured line with the recovery command;
  it must not interpolate `null`. Standalone `set-relay` usage becomes simply
  `Usage: set-relay <url>`.
- `mcp/mesh_server.ts` conditionally supplies `MeshNode.bridge`. Without a
  configured relay, it writes an actionable stderr diagnostic and starts only
  the local UDS mesh; it must not call `toWebSocketUrl` or create a cross-PC
  bridge with `null`.
- Update extension operational documentation from three-level precedence to
  env/config/unconfigured and remove the retired hostname.

**Acceptance criteria**:

- [ ] Absent env/config resolves exactly to `{ url: null, source: "unconfigured" }`.
- [ ] Env and config resolutions remain canonical HTTP(S), with env winning.
- [ ] Start and status paths render an actionable unconfigured outcome without
  creating a `RelayClient`.
- [ ] MCP local mesh remains constructible without a bridge; CLI/docs/tests do
  not name `kDefaultRelayUrl` or the retired relay.

---

### Unit 2: App resolution, I/O boundaries, and non-retryable state

**Files**: `app/lib/data/transport/relay_config.dart`,
`app/lib/data/preferences/preferences.dart`,
`app/lib/config/dependencies.dart`,
`app/lib/data/mesh/mesh_client.dart`,
`app/lib/data/transport/connection_manager.dart`,
`app/lib/ui/pairing/viewmodels/pairing_viewmodel.dart`,
`app/lib/pairing/pair_request_flow.dart`, and matching tests under
`app/test/data/{transport,mesh}/` and `app/test/ui/pairing/`

**Story**: `epic-rebrand-external-surfaces-no-default-relay-app-resolution-handling`

```dart
enum RelaySource { preferences, unconfigured }

sealed class RelayResolution {
  const RelayResolution();
  RelaySource get source;
}

final class ConfiguredRelay extends RelayResolution {
  const ConfiguredRelay(this.url);
  final String url;
  @override
  RelaySource get source => RelaySource.preferences;
}

final class UnconfiguredRelay extends RelayResolution {
  const UnconfiguredRelay();
  @override
  RelaySource get source => RelaySource.unconfigured;
}

RelayResolution resolveRelayUrl(Preferences prefs);

final class RelayNotConfiguredException implements Exception {
  const RelayNotConfiguredException();
}
```

**Implementation notes**:

- `relay_config.dart` owns the sealed type, its user-facing unconfigured
  message, resolution, validation, and `RelayNotConfiguredException`; delete
  `kDefaultRelayUrl`. `Preferences.relayUrl == null` means unconfigured, and
  its comments are updated without changing the stored key/format.
- The pairing ViewModel resolves before disconnecting/opening a transport. On
  `UnconfiguredRelay`, emit a non-retryable pairing error directing the user to
  Settings. `performPairing` remains deliberately typed with a required
  `String currentRelayUrl`; remove its unused resolver import/shim rather than
  allowing an invalid URL into the pairing protocol.
- The production connection factory narrows `ConfiguredRelay` before
  `WsTransport.connect`; otherwise it throws `RelayNotConfiguredException`.
  `ConnectionManager._connect` catches that named exception, emits
  `StatusOffline(reason: <shared message>, canRetry: false)`, and neither
  schedules a retry nor lets its watchdog schedule one. Other failures retain
  the existing retry/backoff behavior.
- `MeshClient` receives `RelayResolution Function()` from DI. `fetch` and
  `publish` check for `UnconfiguredRelay` before URI construction and return
  their existing `MeshFetchFailure` / `MeshPublishFailure` with the shared
  actionable reason. This makes boot-time mesh sync safe even for a legacy
  installation that has peers but no URL.

**Acceptance criteria**:

- [ ] No app transport caller passes an unconfigured value into `Uri.parse`,
  `WsTransport.connect`, URL conversion, or pairing mismatch comparison.
- [ ] A stored URL keeps current configured behavior; absence is observable as
  a sealed state and typed/non-retryable result at each boundary.
- [ ] A non-retryable configuration error cannot become a watchdog retry loop.

---

### Unit 3: Mandatory self-hosted onboarding and Settings recovery

**Files**: `app/lib/ui/onboarding/states/onboarding_state.dart`,
`app/lib/ui/onboarding/viewmodels/onboarding_viewmodel.dart`,
`app/lib/ui/onboarding/widgets/relay_step.dart`,
`app/lib/ui/onboarding/onboarding_page.dart`,
`app/lib/ui/settings/viewmodels/settings_viewmodel.dart`,
`app/lib/ui/settings/settings_page.dart`, and matching tests under
`app/test/ui/{onboarding,settings}/`

**Story**: `epic-rebrand-external-surfaces-no-default-relay-app-onboarding-settings`

```dart
class OnboardingInProgress extends OnboardingState {
  const OnboardingInProgress({
    this.step = OnboardingStep.welcome,
    this.customRelayUrl = '',
    this.customRelayError,
  });

  final OnboardingStep step;
  final String customRelayUrl;
  final String? customRelayError;
}

// SettingsViewModel
RelayResolution get relayResolution => resolveRelayUrl(_prefs);
String get effectiveRelayLabel => switch (relayResolution) {
  ConfiguredRelay(:final url) => url,
  UnconfiguredRelay() => 'Not configured',
};
String get relayUrlOverride => _prefs.relayUrl ?? '';
```

**Implementation notes**:

- Delete `RelayChoice`, `onChoice`, `_RelayCard`, and the Community relay card.
  Keep the existing self-hosted card/form but present it as the required relay
  configuration. `_canContinue` is true only for a valid, non-empty URL.
- On relay-step submit, validate every input (including empty) with
  `relayUrlValidationMessage`; persist only the validated URL, then move to
  pairing. No `null` write represents successful onboarding.
- Settings initializes blank for no stored URL, labels the active state
  `Not configured`, and removes the `Use default Relay` button. Its save path
  remains the recovery action: valid save disconnects and boots the connection
  manager exactly as today. The UI must use the resolver-provided label rather
  than inventing a second absence check.

**Acceptance criteria**:

- [ ] The rendered onboarding page contains no Community relay wording/card and
  cannot enter pairing with a blank URL.
- [ ] The valid self-hosted URL persists before pairing starts.
- [ ] Settings makes legacy/unconfigured state visible, contains no default
  action, and reconnects only after a valid user-supplied URL is saved.

## Implementation order

1. `epic-rebrand-external-surfaces-no-default-relay-extension-unconfigured-state`
   and `epic-rebrand-external-surfaces-no-default-relay-app-resolution-handling`
   run in parallel; they own separate subprojects.
2. `epic-rebrand-external-surfaces-no-default-relay-app-onboarding-settings`
   runs after app resolution handling so it consumes the settled sealed state
   and shared message rather than duplicating absence logic.
3. Run cross-subproject checks and a repository grep for the retired relay
   hostname; update any test mocks/docs in the owning story rather than adding
   compatibility aliases.

## Testing

### Extension

- `config.test.ts`: absent env/config is `unconfigured`; config and env retain
  precedence/canonicalization; delete the former default-constant test.
- `extension.test.ts` and `ping.test.ts`: update resolver mocks to configured
  values when a socket is under test; add start/status no-config assertions
  showing the recovery command and no socket construction.
- Target MCP/CLI behavior with an extracted or existing test seam if practical;
  at minimum typecheck proves the optional bridge handling is exhaustive.

### App

- `relay_config_test.dart`: exact configured vs unconfigured sealed cases and
  retained URL validation/conversion.
- `pairing_viewmodel_test.dart`: no configured relay fails before the transport
  factory; no retry affordance is offered.
- `connection_manager_test.dart`: a `RelayNotConfiguredException` gives one
  non-retryable `StatusOffline` and no retry timer/watchdog reconnect.
- `mesh_client_test.dart`: unconfigured fetch and publish return their typed
  failures without invoking the Dio adapter.
- `onboarding_viewmodel_test.dart` and a focused relay-step widget test: no
  choice enum/card, blank rejects/stays on relay, valid URL persists/advances.
- `settings_viewmodel_test.dart` / `settings_page_test.dart`: blank current
  state displays `Not configured`, default prefill/button are absent, and a
  valid saved URL reboots connection.
- Keep `app/test/ui/update/update_banner_viewmodel_test.dart` in the normal
  Flutter test run as a regression guard; it does not own relay resolution.

## Risks

- **Legacy persisted state**: users who previously relied on the default can
  have a completed onboarding flag and paired peers but no relay URL. Mitigate
  by making mesh, pairing, connection, and Settings each handle the explicit
  state; do not infer a replacement host or clear pairings.
- **Retry convergence**: treating configuration like a network failure would
  produce infinite reconnect traffic and hide the remediation. The named
  exception plus `StatusOffline(canRetry: false)` and watchdog guard is the
  required containment.
- **Two extension start paths and MCP startup**: one missed branch either
  crashes on `null` or keeps the old fallback alive. Resolver union typing,
  direct tests, and a repo-wide `kDefaultRelayUrl`/hostname grep make these
  omissions visible.

## Verification notes

- `flutter analyze` was available on PATH and passed cleanly.
- `corepack pnpm typecheck` passed from `pi-extension/` with the prescribed
  writable cache environment. pnpm required `CI=true` in this non-TTY harness
  to recreate its ignored local `node_modules/`; no tracked dependency file
  changed.

## Review (2026-07-15, standard, cross-model fresh-context)

Reviewer: `openai-codex/gpt-5.6-sol` (different model class from the umans
orchestrator). One balanced pass over the integrated feature diff
(`376fa38..HEAD`), focused on removing the hardcoded default relay URL.

### Findings (adjudicated)
- **Important — docs direct users to a removed command and claim a default exists.** `pi-extension/README.md:173` instructed `/outpost-pi config` (removed command) and promised an `env / config / default` result; `site/src/app/docs/page.tsx:428` repeated the removed command. The implementation registers `/outpost-pi status` (`pi-extension/src/index.ts:1743`) and explicitly tests that `/outpost-pi config` is absent (`pi-extension/src/extension.test.ts:363`). Replaced both command examples with `/outpost-pi status` and described the actual `unconfigured` / `off` / `on` states + the `set-relay` recovery action. **Fixed.**
- No other findings; no-default-relay behavior is correct across app and extension (non-retryable app state, local-only MCP mesh).

### Verification of fixes
- `corepack pnpm typecheck` + `corepack pnpm test` (pi-extension) green.
- `corepack pnpm lint` + `corepack pnpm build` (site) green.

### Verdict
Approve. Advanced `review → done`.
