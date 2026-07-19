# Run notes — implement-orchestrator 2026-07-18 (resilience epic)

## Scope

3 implementing features + 2 standalone stories from
`epic-remote-session-resilience-refactor` (just designed). All at `stage:
implementing` (features) or `drafting` (stories, dependency met).

## Topology

### Conflict graph (write sets)

- F1 (outbound-buffer, pi-extension) — `owner_multiplexer.ts`, `ports.ts`,
  `owner_multiplexer.test.ts`. May touch `index.ts:331-347` (peer_offline
  consumption) — SERIALIZE with the 2 standalone stories (both touch `index.ts`
  command helpers / extension tests).
- F2 (tui-parity, app) — `domain/session_state.dart`, `transcript_projection.dart`,
  `chat_state.dart`, `chat_viewmodel.dart`, `chat_page.dart`, `input_bar.dart`.
- F3 (mobile-session-control, app) — `quick_actions_sheet.dart`,
  `quick_actions_viewmodel.dart`. Adjacent to F2's files (both `app/lib/ui/chat/`)
  but different subdirectory. SERIALIZE to be safe.
- 2 standalone stories (pi-extension) — `index.ts` command helpers +
  `actions/handlers.test.ts` + extension-level tests. SERIALIZE with F1.

### Waves

**Wave 1 (2 parallel — disjoint subprojects):**
| Worker | Item | Model | Effort |
|---|---|---|---|
| W1 | F1 outbound-buffer-on-peer-offline | sol | high |
| W2 | F2 mobile-tui-parity-chat-resilience | sol | high |

**Wave 2 (2 parallel — after Wave 1 commits):**
| Worker | Item | Model | Effort |
|---|---|---|---|
| W3 | F3 mobile-native-session-process-control | luna | high |
| W4 | 2 standalone stories (stale-command-ui-notify-guard + stale-action-boundary-regression-tests) | luna | medium |

## Effective review_weight

`standard` (default).

## Environment (same as prior run — pass to workers)

### pi-extension (F1, standalone stories)
- Use `./node_modules/.bin/tsc --noEmit` / `./node_modules/.bin/vitest run <path>`
  directly (corepack pnpm broken: read-only COREPACK_HOME).
- Known flakes: `env-ext-test-cwd-lock-ordering-flake` + `cwd_lock.test.ts`
  (7 tests, `EROFS: read-only /tmp` mkdtemp). Pre-existing env issues; document
  honestly; don't weaken. Prefer targeted vitest paths.

### app (F2, F3)
- Flutter at `~/projects/outpost_pi/.tools/flutter`. Set
  `PUB_CACHE=/home/agent/projects/outpost_pi/.pub-cache`.
- `flutter analyze lib test` (scoped — full analyze shows ~228 pre-existing
  errors in `packages/outpost_pi_identity/test/`, NOT the app).
- `flutter test --concurrency=1` (serial — parallel runner has scheduler flakes).
- `flutter build apk --debug` memory-sensitive; skip with documented reason if OOM.

## Baseline

- pi-extension: tsc clean, vitest 843/854 (8 env flakes).
- app: analyze (lib+test) clean, 739 tests serial.
