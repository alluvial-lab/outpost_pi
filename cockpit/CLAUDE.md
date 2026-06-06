# Remote Pi — Cockpit (Flutter Desktop)

Cliente **desktop** (macOS first) do Remote Pi. GUI multi-pane sobre o motor do
Pi: projetos à esquerda, agentes no centro, árvore de arquivos à direita. Cada
agente é um `pi --mode rpc` que o app spawna e dirige **localmente** — sem relay,
sem pareamento, sem crypto. É a contraparte local do `app/` (que é o gateway
remoto). Plano de referência: [`../plan/37-desktop-cockpit.md`](../plan/37-desktop-cockpit.md).

## Escopo atual (MVP — provar o conceito)

Fase de validação: provar que o Flutter desktop aguenta o `--mode rpc` — spawn de
child process, streaming de stdout, `send` por stdin, kill limpo. **Layout básico
primeiro; panes (multiplexação) ainda NÃO** — decisão adiada (ver plano 37). Nada
de relay/mesh/crypto nesta fase.

Decisões fechadas (plano 37, 2026-06-05):

| # | Decisão |
|---|---|
| **A** | Código mora aqui em `cockpit/` (não dentro de `app/`). Reuso futuro com `app/` via `packages/pi_core` — **ainda não extraído** |
| **B** | Spawna `pi --mode rpc` **puro**, sem a extensão remote-pi. Local-only, sem relay |
| **C** | Spawn **próprio** — não reusa o supervisor do plano 26 (que é fire-and-forget sem streaming) |

## Stack

- Flutter desktop / Dart (mesma major do `app/`)
- Plataforma: **macOS first** (Windows/Linux possíveis via Flutter, não testados)
- State management: `ViewModel<T>` (`ChangeNotifier` single-field) + `provider`
- DI: `auto_injector` (registry em `lib/config/`)
- Roteamento: `go_router`
- Resultado tipado: `Result<T, E>`
- Subprocesso: `dart:io` `Process.start` (spawn do `pi --mode rpc`)
- Menu nativo: `PlatformMenuBar`

> É a **mesma arquitetura do `app/`**. A única diferença real de camadas está em
> `data/`, que aqui gerencia **processos RPC + filesystem** em vez de
> mesh/relay/crypto. O resto (config, domain, routing, ui) segue idêntico.

## Comandos

- `flutter pub get` — instala deps
- `flutter analyze` — lint estático (deve passar zero issues)
- `flutter test` — testes
- `flutter run -d macos` — abre no desktop
- `dart format .` — formata
- `flutter build macos` — build verificável

## Arquitetura por camadas

O `lib/` segue a **mesma organização do `app/`**, com responsabilidades estritas.
Cada pasta tem seu próprio `CLAUDE.md` descrevendo a persona daquela camada —
**leia o CLAUDE.md da camada antes de editar qualquer arquivo dentro dela**.

```
lib/
├── main.dart
├── config/          # Bootstrap, DI, env, setup global  → config/CLAUDE.md
│   └── utils/       # Helpers horizontais
├── domain/          # Entidades, use cases, validators  → domain/CLAUDE.md
│   └── contracts/   # Interfaces de baixo nível (process, filesystem)
├── data/            # RPC process, filesystem, repos     → data/CLAUDE.md
├── routing/         # GoRouter, paths, guards            → routing/CLAUDE.md
└── ui/              # Páginas + ViewModels por feature   → ui/CLAUDE.md
    ├── core/
    │   ├── themes/      # tema dark (context.colors / context.typo)
    │   └── viewmodel/   # ViewModel<T> base
    └── <feature>/
        ├── states/
        ├── viewmodels/
        ├── widgets/
        └── <feature>_page.dart
```

Regra de ouro do fluxo de dependência (idêntica ao `app/`):

```
ui ──► domain ◄── data
        ▲
        │
     config (injeta tudo)
     routing (compõe rotas + ViewModels)
```

- `domain/` **não** importa nada de `data/`, `ui/`, `routing/`, `config/`.
- `data/` implementa contratos de `domain/`, nunca importa de `ui/`.
- `ui/` consome `domain/` (use cases) via ViewModels — nunca chama `data/` direto.
- `config/` é o único lugar que conhece todas as camadas (para registrar bindings).

## Convenções

- **Naming**: arquivos `snake_case.dart`, classes `PascalCase`, widgets `PascalCase`
- **Imports**: relativos dentro do mesmo feature; absolutos via `package:cockpit/...`
  quando cruzando features ou camadas
- **Barrel files**: cada feature/módulo pode expor um `<nome>.dart` agregando os
  símbolos públicos; consumidores externos importam só o barrel
- **Async**: prefira `Future`/`Stream` tipados, evite `dynamic` (o stream de
  eventos RPC é tipado em `domain/`, nunca `Map<String, dynamic>` cru na `ui/`)
- **Erros**: `Result<T, E>` ou exceptions tipadas; nunca `catch (e)` genérico em produção
- **ViewModels**: registrados em `config/` e injetados em `routing/` via Provider;
  páginas nunca instanciam ViewModel diretamente — sempre `context.watch/read/select`
- **Tema**: nunca hardcode `Color(0x…)` / `TextStyle(fontFamily:…)`; leia via
  `context.colors.<token>` / `context.typo.<estilo>` (barrel `ui/core/themes`)

## Regra crítica: `BuildContext` em código assíncrono

Acessar `context` após um `await` (ou dentro de `.then/.onSuccess/.flatMap/.whenComplete`)
pode crashar com `Null check operator used on a null value` se o widget já tiver
sido desmontado. O lint `use_build_context_synchronously` **não detecta** callbacks
encadeados — a prevenção é manual.

```dart
// CORRETO — await + guard
final result = await viewModel.spawnAgent();
if (!mounted) return;           // em StatefulWidget
// if (!context.mounted) return; // em StatelessWidget
context.useContextSomehow();
```

```dart
// ERRADO — context dentro de callback assíncrono
await viewModel.spawnAgent().onSuccess((_) {
  context.useContextSomehow(); // CRASH se desmontado
});
```

> Nunca use `context` dentro de `.onSuccess()`, `.onFailure()`, `.flatMap()`,
> `.then()` ou `.whenComplete()`. Sempre transforme para `await` + guard.

## NÃO fazer

- Editar arquivos fora de `cockpit/`
- Adicionar **relay, mesh, crypto ou pareamento** nesta fase — Cockpit é
  local-only (decisão B). Reachability remota é evolução futura (plano 37)
- Criar **panes/multiplexação** antes de revalidar o conceito com layout básico
  (plano 37 — panes deliberadamente adiados)
- Reusar o supervisor do plano 26 (decisão C — spawn próprio)
- Implementar crypto manual (não há crypto nesta fase)
- Comitar `build/`, `.dart_tool/`, `macos/Pods/`
- Adicionar dependência sem registrar no plano 37
- Misturar responsabilidades entre camadas — quando bater dúvida, leia o
  CLAUDE.md da camada alvo

## Modo orquestrado

Se receber um prompt começando com `[ORCH:<task-id>]`, leia
[`../.orchestration/INSTRUCTIONS.md`](../.orchestration/INSTRUCTIONS.md) antes de
qualquer outra ação. Esse marker indica que outro agente está coordenando o
trabalho e tem regras específicas (onde escrever resultado, não comitar, etc).
