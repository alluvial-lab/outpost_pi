# [ORCH:probe-relay-folder] Estrutura de pastas do relay

**Status**: done
**Arquivos tocados**: nenhum

## Resumo

Relay é um crate Rust minimal: apenas `src/main.rs` + `Cargo.toml` + `Cargo.lock`.
Nenhuma subpasta de módulos ainda — toda lógica está em arquivo único.

## Notas pro orquestrador

```
/relay
├── .gitignore
├── Cargo.lock
├── Cargo.toml
├── CLAUDE.md
└── src/
    └── main.rs
```

Estrutura extremamente simples. Quando a implementação crescer, será necessário
modularizar `src/` (ex: `src/handler.rs`, `src/state.rs`).
