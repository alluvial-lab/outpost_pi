---
name: documentation-conventions
description: >
  Outpost-Pi inline-documentation convention for the human/agent combo.
  Native doc framework per language (JSDoc for TypeScript, dartdoc for Dart,
  rustdoc for Rust) with a three-tier intent model (Always / Recommended / Skip)
  and agent-scan enforcement. Read before writing or reviewing code comments
  across pi-extension/, app/, cockpit/, relay/, or site/. Adapted from the
  SNC/platform convention.
---

# Inline Documentation Convention

Native-language doc comments focused on **intent and contracts** — never
restate type information the signature already carries. The audience is both
human readers (IDE hover, rendered doc site) and coding agents (raw-comment
read); optimize for the agent reading the comment next to the code, since
Outpost-Pi publishes no external API surface (local-path extension, not npm;
apps sideloaded, not on a store with a doc site).

## Native framework per language

| Surface | Tool | Syntax | Renders to |
|---|---|---|---|
| `pi-extension/` (TS) | JSDoc | `/** */` | IDE hover (no published site) |
| `app/`, `cockpit/` (Dart) | dartdoc | `///` | IDE hover; pub.dev if ever published |
| `relay/` (Rust) | rustdoc | `///` | IDE hover; `cargo doc` if ever generated |
| `site/` (React/TS) | JSDoc on exported components/hooks | `/** */` | IDE hover |

Use the language-native tool — do not invent a cross-language format. The
three-tier model below is language-agnostic; the syntax is per-language.

## Tiers

| Tier | Scope | Requirement |
|---|---|---|
| **Always** | Exported functions/types/classes from shared/domain layers, service-layer functions, middleware/factory functions, `Result`/`Either`/discriminated-union-returning functions, ViewModel exports, hook exports, context providers, `pub` items in `relay/` | Must have a doc comment |
| **Recommended** | Route/command handlers beyond a declared contract, complex internal helpers (>20 lines or non-obvious logic), exported React components with 3+ props, `lib/`/`utils/` helpers, exported Flutter widgets with 3+ params | Should have a doc comment |
| **Skip** | Schema/DTO declarations that restate a wire shape, `index.ts`/`index.dart` barrel re-exports, CSS, test files, self-documenting constants, trivial private helpers (<10 lines), generated code | No doc needed |

The tier is keyed to **intent**, not type. "Always" captures things whose
*purpose* isn't obvious from the signature (contracts, side effects,
non-obvious returns); "Skip" captures things the signature already explains.

## What to Write

- **One-line summary** in imperative mood: "Resolve the relay URL.", "Forward
  a cross-PC pi envelope.", "Build the room-id derivation."
- **Contract notes** when non-obvious: pre-conditions, side effects, error
  behavior, concurrency, lifecycle ownership, dependencies on middleware or
  caller-provided context.
- **Parameters** — only when name + type is insufficient (e.g. `options`
  objects, flags with non-obvious meaning, a `cwd` that must be realpath'd).
- **Returns** — only for `Result<T>`/`Either`/discriminated unions where the
  shape isn't obvious from the type, or where a null return carries meaning.
- **Throws/errors** — always when a function throws (vs. returning a
  `Result`/`Either`). In Rust, use a `# Errors` section; in Dart/TS, a
  `@throws` tag.
- **Example** — for shared utilities with non-obvious usage.

## What NOT to Write

- Redundant type restatement: `@param id - the user ID (string)` when the
  signature is `userId: string`.
- Implementation details that change with refactoring (state internals,
  algorithm steps).
- Obvious descriptions: `/// The user model.` on `class User`.
- Type annotations in tags (`@param {string}`) — the language carries types.
- PT (Portuguese) — all comments are EN (see
  `epic-rebrand-to-outpost-pi-en-first`).

## Format per language

### TypeScript (`pi-extension/`, `site/`)

```typescript
/** Resolve the effective relay URL in canonical http(s):// form. */
export function resolveRelayUrl(): RelayResolution { ... }

/**
 * Forward a cross-PC pi envelope to a sibling leader's room.
 *
 * Targets the cached leader_room; on a stale room post-failover, the ACK
 * times out and the next peers_update re-warms the cache.
 *
 * @param toPc - sibling Pi pubkey (base64), NOT a pc label
 * @returns true if packed onto the relay (best-effort; ACK is async)
 */
export function sendEnvelopeToPi(toPc: string, toRoom: string, env: Envelope): boolean { ... }
```

### Dart (`app/`, `cockpit/`)

```dart
/// Resolve the effective relay URL.
///
/// Returns [ConfiguredRelay] when a URL is stored or injected; returns
/// [UnconfiguredRelay] when neither env nor preference supplies one — the
/// caller must surface this as an actionable error, not a silent fallback.
RelayResolution resolveRelayUrl(Preferences prefs) { ... }

/// Pair with a Pi over the relay.
///
/// Refuses an unconfigured relay before opening a transport. Single-use
/// token; throws [PairTokenExpired] after 60s.
///
/// Throws [PairError] on token consumed/unknown/internal failure.
Future<PairResult> pair(PairRequest req) { ... }
```

### Rust (`relay/`)

```rust
/// Forward a cross-PC `pi_envelope` to one destination room.
///
/// Room-targeted: only the addressed room of the destination peer receives
/// the frame; the sender's own connection is skipped. The generic envelope
/// body is carried verbatim — the relay never parses `session_id` or `ct`.
///
/// # Errors
///
/// Returns [`PiForwardResult::TransportError`] with `bad_envelope` when
/// `to_pc` or `to_room` is empty, `not_authorized` when the sender is not a
/// sibling of `to_pc`, or `offline` when no live connection exists at
/// `(to_pc, to_room)`.
pub(crate) async fn handle_pi_envelope(
    sender_peer_id: &str,
    frame: PiEnvelopeFrame,
) -> PiForwardResult { ... }
```

## Enforcement

Agent-scan via the `scan-documentation` rule library
(`.agents/skills/scan-documentation/SKILL.md`), auto-loaded by the
`gate-refactor` glob `scan-*/SKILL.md`. Findings land as refactor-gate items
tagged `(documentation)`. No ESLint/clippy hard-enforcement — the agent scan
fits the existing `scan-*` stack this repo already uses
(`scan-boundaries`, `scan-lifecycle`, `scan-protocol-contract`).

## Convention rationale

- **Native tool over a cross-language format.** Each language has a canonical
  doc tool that renders and IDE-hovers correctly; JSDoc/dartdoc/rustdoc are
  what agents and IDEs expect. Inventing a unified format would lose tooling
  integration for no cross-language benefit.
- **Intent over types.** The signature already carries types; the doc carries
  *why*, *when*, and *what can go wrong*. Restating types is noise that drifts.
- **Three-tier model.** "Always" captures contract-bearing surfaces;
  "Skip" avoids mandating docs on self-evident code. A blanket "document
  everything" rule produces obvious-description noise; a blanket "only when
  asked" rule leaves contracts undocumented. The tier split matches the
  intent-vs-types distinction across all four language surfaces.
- **Agent-scan over linter enforcement.** Rule-tuning linters (ESLint
  jsdoc, clippy pedantic) are false-positive-prone and add a dependency.
  The existing `scan-*` agent-scan stack catches drift without per-language
  linter config. Matches the SNC/platform posture this convention adapts.
- **Adapted from SNC/platform** (`.claude/rules/inline-documentation.md`),
  which proved the three-tier + agent-scan approach on a TS-only application.
  Outpost-Pi extends it to Dart and Rust; the philosophy transfers, the syntax
  is per-language.

## Revisit if

- Agent scanning proves unreliable at catching missing or drift-prone docs in
  Dart/Rust (where the `scan-documentation` rules are newly adapted, not
  battle-tested) — add clippy/eslint enforcement as the lesser evil.
- Outpost-Pi publishes an external API surface (npm package, pub.dev package,
  crates.io crate) — at that point the stricter validation of TSDoc +
  API-Extractor / dartdoc generation / docs.rs earns its weight over terse
  intent comments.
- The agent-vs-rendered-doc-site tension becomes real: today Outpost-Pi
  publishes nothing, so optimizing for the agent reading the raw comment is
  correct. If a rendered human-facing doc site becomes a goal, richer
  examples and prose may be warranted for the published surface.
- The three-tier Always/Recommended/Skip keeps producing false positives on
  Dart/Rust edge cases (e.g. trait impls, Flutter widget `build()` overrides).
