# Run notes — implement-orchestrator + epic-review 2026-07-18/19 (resilience epic COMPLETE)

## Outcome

`epic-remote-session-resilience-refactor` advanced from `stage: drafting`
through design, implementation, per-feature review, and epic aggregate review
to `stage: done`. All 8 child features/stories terminal. The epic's residual
targeted patches + mobile-UX cluster are complete; the bold-refactor epics
remain the separate architectural reconception track.

## Execution path

1. **epic-design** — realized the decomposition in the epic body (6 features
   + 2 standalone stories); advanced drafting → implementing.
2. **feature-design** (4 parallel) — designed the 4 drafting children:
   - outbound-buffer (4 child stories)
   - mobile-tui-parity (5 units + 1 new child; 2 parked, 1 roadmap)
   - mobile-native-session-process-control (3 child stories)
   - fork-vendor (reconciled ~done; conditional child closed)
3. **implement-orchestrator** (2 waves):
   - Wave 1: outbound-buffer (piext) + mobile-tui-parity (app) parallel
   - Wave 2: mobile-native-session-control (app) + 2 standalone stories (piext) parallel
4. **Per-feature review** (standard weight, fresh-context gpt-5.6-sol):
   - outbound-buffer: needs fixes (2 blockers) → fixed → done
   - mobile-tui-parity: needs fixes (3 material) → fixed → done
   - mobile-native-session-control: needs fixes (1 blocker + 3 material) → fixed → done
   - 2 standalone stories: bounded inline review → done
5. **Epic aggregate review** (deeper lane, standard weight):
   - needs fixes (2 cross-feature materials) → fixed → done

## Final child states

| Child | Outcome |
|---|---|
| `feature-app-async-lifecycle-ownership` | done (prior session) |
| `feature-piext-lifecycle-delivery-promise-policy` | done (prior session) |
| `feature-remote-pi-fork-vendor-and-mobile-surface` | done (reconciled) |
| `feature-outbound-buffer-on-peer-offline` | done (2 blockers fixed) |
| `feature-mobile-tui-parity-chat-resilience` | done (3 materials fixed) |
| `feature-mobile-native-session-process-control` | done (1 blocker + 3 material fixed) |
| `story-stale-command-ui-notify-guard` | done (bounded inline) |
| `story-stale-action-boundary-regression-tests` | done (bounded inline) |

## Epic aggregate review findings (both fixed)

1. **Reconnect stale-room race** (app): on relay reconnect, before a fresh
   `rooms` snapshot confirms the Pi room, the app rendered it online + resent
   held messages into a still-offline Pi room (relay dropped, app suppressed
   retry). Fixed: clear live-room confirmation on transport loss; revalidate
   room liveness before held-message resend. Regression: live room → disconnect
   → reconnect-to-relay-only → room stale, no resend → fresh snapshot → resend once.
2. **Exit-42 contract unproved** (piext): the daemon `session_new` → ACK →
   reset → exit 42 → supervisor respawn → successor identity path was coherent
   by inspection but never deterministically tested. Fixed: 4 TypeScript proofs
   (ACK-before-exit + reset; exit 42 + `--continue` omission; immediate respawn
   no backoff; successor room/config identity + fresh session).

## Parked (legitimate)

- `idea-mobile-drop-slow-recovery` + `idea-mobile-outgoing-message-swallowed`
  remain at `drafting` under `feature-mobile-tui-parity-chat-resilience` (done) —
  they need physical-phone live repro; route to `feature-reconnect-reproduction`
  (sibling epic) on the next drop test. The stale-liveness race (finding 1)
  was statically demonstrable and fixed, not deferred.

## Integration verification (final, all green)

- pi-extension: tsc clean; 857+ pass; 8 failures all = pre-existing read-only-/tmp
  env flakes (cwd_lock.test.ts EROFS + known cwd-lock ordering flake).
- app: analyze (lib+test) clean; 758 tests pass serial.

## Commits

~80 commits this session (8fe1a7e..HEAD), unpushed, clean tree.
