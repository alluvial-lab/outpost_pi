# `data/` Layer

## Purpose

Translate `domain/` contracts into calls to external integrations (network,
database, platform), applying caches, mappers, and specialized repositories.
This layer is the boundary between pure business rules and the messy world of
I/O.

## Must do

1. **Implement domain contracts** — every interface declared in
   `domain/repositories/` or `domain/services/` has its concrete implementation
   here.
2. **Translate DTOs** — adapters/mappers convert transport models (JSON,
   database rows) into domain entities and vice versa.
3. **Orchestrate multiple sources** — combine local cache, remote API, and
   storage while exposing a simple API to use cases.
4. **Propagate contextualized failures** — capture technical exceptions from
   integrations and convert them into errors the domain can understand.

   Required API pattern (`data/apis/`):

   ```dart
   try {
     // network / IO call
   } on DioException catch (e, s) {
     return Failure(
       AppException.create(
         'Contextualized message.',
         stackTrace: s,
         originalError: e,
       ),
     );
   } catch (e, s) {
     return Failure(
       AppException.fatal(
         'Unexpected error.',
         stackTrace: s,
         originalError: e,
       ),
     );
   }
   ```

   Rules:
   - `DioException` (network/HTTP error) → `AppException.create(...)`
   - Generic/unexpected error → **always** `AppException.fatal(...)`
   - Stack trace: use the captured `s`; avoid `StackTrace.current` inside
     `catch`
   - Invalid contract / absent data → prefer
     `Failure(AppException.create('...'))` for readable messages and
     consistent tracking by the global observer

5. **Keep contracts explicit** — interfaces live in the domain and
   implementations live here (never the reverse).

## Must not do

1. **Implement business rules** — domain decisions (validations, calculations,
   policies) remain in `domain/`.
2. **Consume UI** — no imports of `ui/`, `widget`, or `BuildContext`.
3. **Access `auto_injector` directly** outside setup — instances are supplied
   through `config/dependencies.dart`.
4. **Duplicate infrastructure logic** — HTTP, WebSocket, and mDNS clients are
   encapsulated in `data/services/`, not scattered throughout the codebase.

## Suggested structure

```
data/
├── adapters/         # DTO ↔ entity mappers (by aggregate)
├── apis/             # HTTP clients (each implements a contract)
├── repositories/     # domain repository implementations
├── services/         # domain service implementations (mDNS, WS, ...)
└── usecases/         # use-case implementations that depend on IO
```

## Vocabulary

- **Repository** — concrete implementation that satisfies a domain contract
  using data sources.
- **Data Source** — specific source (remote, local, cache) used by a
  repository.
- **Adapter / Mapper** — object that converts service DTOs into domain
  entities.
- **Sync Strategy** — policy defining when to fetch remotely, serve cache, or
  merge results.
