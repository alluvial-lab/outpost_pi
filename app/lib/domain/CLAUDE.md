# `domain/` Layer

## Purpose

Materialize business knowledge. This is where models, use cases, and validators
with deterministic rules live, **independent of UI, database, or network**.
This layer is the core — every other layer depends on it; it depends on none.

## Must do

1. **Model entities and value objects** with immutability and consistent
   equality (`==` / `hashCode`).
2. **Orchestrate rules through Use Cases**: each `*UseCase` exposes a single
   domain verb and delegates integrations to contracts (`repositories/`,
   `services/`).
3. **Validate invariants** in `validators/`, throwing typed exceptions
   (`ValidationException`, `DomainException`).
4. **Maintain purity**: predictable synchronous or asynchronous code, without
   side effects beyond calls to contracts.
5. **Expose contracts**: abstract repository and service interfaces belong
   here — concrete implementations live in `data/`.

## Must not do

1. **Import Flutter** — no `BuildContext`, widgets, `Material`, or
   `Cupertino`. Use plain Dart.
2. **Access infrastructure directly** — databases, HTTP, mDNS, and platform
   channels belong in `data/services/`.
3. **Keep global mutable state** — avoid singletons; objects arrive through the
   injector when needed.
4. **Duplicate logic** — reuse existing validators and models rather than
   recreate rules in each use case.
5. **Know transport details** — if a rule must decide between "fetch from cache
   or network", that decision belongs to `data/`, not here.

## Suggested structure

```
domain/
├── entities/           # objects with identity (id + lifecycle)
│   └── <aggregate>/
├── value_objects/      # immutable values without identity (Email, CPF, ...)
├── dtos/               # transfer objects between layers
├── contracts/          # low-level interfaces (clients, gateways)
├── repositories/       # repository interfaces
├── services/           # domain service interfaces
├── usecases/           # unit operations (one verb each)
├── validators/         # invariants and validation rules
└── exceptions/         # typed domain exceptions
```

## Vocabulary

- **Entity** — object with its own identity (`id`) and lifecycle.
- **Value Object** — immutable value without identity (for example, `Email`,
  `Hostname`).
- **Use Case** — unit domain operation exposed to the application.
- **Invariant** — rule that must always be true for the domain to remain
  consistent.
- **Contract** — interface declared in the domain and implemented in `data/`.
