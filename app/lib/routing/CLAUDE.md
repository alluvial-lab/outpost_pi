# `routing/` Layer

## Purpose

Describe and coordinate application routes, connecting paths to pages/flows
without introducing UI or domain logic. This layer supports `GoRouter`, defines
guards, and ensures consistency between declared routes and actual navigation.

## Must do

1. **Centralize paths** — keep constants (for example, `routePaths`) to avoid
   magic strings and simplify refactors.
2. **Define navigation topology** — routes, shells, branches, and redirects
   belong here.
3. **Delegate page construction** — each route instantiates only its
   corresponding root widget (for example, `HomeRoute`); the `ui/` feature owns
   the content.
4. **Apply middleware/guards** — authentication, permission checks, and
   onboarding are encapsulated in `redirect`/route guards.
5. **Document flows** — always make clear which route starts each module and
   how the user returns.
6. **Inject ViewModels into the tree** — composition of `MultiProvider` and
   `ViewmodelProvider`s happens exclusively in `routing/router.dart`, ensuring
   a single orchestration point per route.

## Must not do

1. **Access stores or services directly** — business logic belongs to the
   domain and the UI consumes it through ViewModels.
2. **Create global side effects** — no initialization or tracking here; only
   navigation.
3. **Duplicate routes in features** — every path change goes through
   `routing/` to avoid inconsistencies.
4. **Mix responsibilities** — avoid inline widgets or feature-specific logic;
   use only widgets declared in `ui/`.

## Suggested structure

```
routing/
├── router.dart          # GoRouter + MultiProvider/ViewmodelProvider
├── routes.dart          # path constants (routePaths.home, ...)
└── guards.dart          # redirect logic (auth, onboarding, ...)
```

## Vocabulary

- **Route Path** — string declared in `routes.dart` that identifies a
  navigation route.
- **Shell Route** — structure that retains navigation state (for example,
  tabs) and injects `NavigationShell`.
- **Route Guard** — verification function before `builder`/`pageBuilder`.
- **Entry Widget** — top-level widget of a feature (for example, `HomeRoute`)
  responsible for providers and wrappers.
