# Outpost-Pi — App (Flutter)

Outpost-Pi mobile client (iOS + Android). Pairs via QR, lists Pi sessions,
chat with streaming, approval cards for tool calls.

Before editing or reviewing `app/`, also read the agent-neutral reference
`../.agents/skills/flutter-mobile/SKILL.md`. For state/reconnect changes that cross
app/extension/relay, read `../.agents/skills/mobile-remote-coding/SKILL.md`.

## Stack

- Flutter 3.41+ / Dart 3.11+
- Platforms: iOS, Android
- State management: `ChangeNotifier` + `provider` (reactive ViewModels)
- DI: `auto_injector` (registry in `lib/config/`)
- Routing: `go_router`
- Outcomes: feature-specific sealed result hierarchies (for example, mesh fetch/publish) plus typed exceptions such as `PairingError`
- Crypto: `package:cryptography` (X25519 / Ed25519 / HKDF-SHA256 / XChaCha20-Poly1305 — the owner-channel E2E stack in `lib/data/transport/secure_channel.dart`)
- WebSocket: `web_socket_channel` or similar

> Still-open decisions (final state management) live in
> `../plan/00-decisions.md`. The stack above is the current direction based on the
> inherited architecture; structural changes require a new plan.

## Commands

The Flutter SDK and pub cache live in the repository (not in `/opt` or `/tmp`).
Set `PUB_CACHE` and use the binary in `.tools/flutter`. `app/` has no git dependencies,
so online `pub get` works (or `--offline` if the cache is already populated).

```bash
cd app
export PUB_CACHE=~/projects/outpost_pi/.pub-cache
~/projects/outpost_pi/.tools/flutter/bin/flutter pub get
~/projects/outpost_pi/.tools/flutter/bin/flutter analyze              # no warnings or errors
~/projects/outpost_pi/.tools/flutter/bin/flutter test --exclude-tags e2e
# From the repository root, run the dedicated E2E pairing harness:
# e2e/run-pairing.sh
~/projects/outpost_pi/.tools/flutter/bin/flutter build apk --debug    # or --no-codesign ios
```

- `dart format .` — formats (or `~/.tools/flutter/bin/cache/dart-sdk/bin/dart format .`)

Note: `flutter analyze` in `app/` emits one known `deprecated_member_use` `info` at
`lib/ui/chat/widgets/input_bar.dart:806` (`axisAlignment`; explanatory comment at line 802). Do not fail reviews because of it.

> For the complete APK build path on the dev VM (`codebox`) — JDK 21 toolchain
> + Android SDK API 36, `--release --split-per-abi` build (~31 MB per ABI), and the
> two build gotchas (`.` vs `source` in dash jobs; complete wipe of
> `~/.gradle` for Kotlin-DSL workspace corruption) — see the agent-neutral
> reference `../.agents/skills/flutter-mobile/SKILL.md` ("Android APK build on the
> dev VM" section).

## Layered architecture

`lib/` is organized into layers with strict responsibilities. Each directory
has its own `CLAUDE.md` describing that layer's role — **read the layer's
CLAUDE.md before editing any file within it**.

```
lib/
├── main.dart
├── config/          # Bootstrap, DI, env, global setup  → config/CLAUDE.md
│   └── utils/       # Cross-cutting helpers
├── domain/          # Entities, use cases, validators   → domain/CLAUDE.md
├── data/            # Repositories, adapters, APIs      → data/CLAUDE.md
├── routing/         # GoRouter, paths, guards           → routing/CLAUDE.md
└── ui/              # Pages + ViewModels by feature     → ui/CLAUDE.md
    └── <feature>/
        ├── states/
        ├── viewmodels/
        ├── widgets/
        └── <feature>_page.dart
```

Dependency-flow golden rule:

```
ui ──► domain ◄── data
        ▲
        │
     config (injects everything)
     routing (composes routes + ViewModels)
```

- `domain/` **does not** import anything from `data/`, `ui/`, `routing/`, or `config/`.
- `data/` imports contracts from `domain/`, never from `ui/`.
- `ui/` ViewModels consume selected `data/` repositories/services directly; pages still interact through their ViewModels.
- `config/` is the only place that knows all layers (to register bindings).

## Conventions

- **Naming**: `snake_case.dart` files, `PascalCase` classes, `PascalCase` widgets
- **Imports**: relative within the same feature; absolute through `package:app/...`
  when crossing features or layers
- **Barrel files**: each feature/module can expose a `<name>.dart` aggregating
  public symbols; external consumers import only the barrel
- **Async**: prefer typed `Future`/`Stream`, avoid `dynamic`
- **Errors**: prefer feature-specific sealed outcomes or typed exceptions; at infrastructure boundaries, convert catch-alls to safe typed outcomes or bounded-context logs
- **ViewModels**: registered in `config/` and injected in `routing/` through Provider;
  pages never instantiate ViewModels directly — always use `context.watch/read/select`

## Critical rule: `BuildContext` in asynchronous code

Accessing `context` after an `await` (or inside `.then/.onSuccess/.flatMap/.whenComplete`)
can crash with `Null check operator used on a null value` if the widget has already been
disposed. The `use_build_context_synchronously` lint **does not detect** chained
callbacks — prevention is manual.

**Required pattern**:

```dart
// CORRECT — await + guard
final result = await viewModel.doSomething();
if (!mounted) return;          // in StatefulWidget
// if (!context.mounted) return; // in StatelessWidget
context.useContextSomehow();
```

```dart
// WRONG — context inside asynchronous callback
await viewModel.doSomething().onSuccess((_) {
  context.useContextSomehow(); // CRASH if disposed
});
```

> Never use `context` inside `.onSuccess()`, `.onFailure()`, `.flatMap()`,
> `.then()`, or `.whenComplete()`. Always convert to `await` + guard.

## Do NOT

- Edit files outside `app/`
- Implement crypto manually — use `package:cryptography` (the canonical app crypto package)
- Commit `build/`, `.dart_tool/`, `ios/Pods/` (already in the root `.gitignore`)
- Add a dependency without recording it in the corresponding plan
- Mix responsibilities between layers — when in doubt, read the target layer's
  CLAUDE.md

## Orchestrated mode

If you receive a prompt starting with `[ORCH:<task-id>]`, read
`../.orchestration/INSTRUCTIONS.md` before any other action. This marker
indicates another agent is coordinating the work and has specific rules
(where to write results, do not commit, etc.).
