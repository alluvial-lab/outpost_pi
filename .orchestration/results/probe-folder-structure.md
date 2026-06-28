# [ORCH:probe-folder-structure] Estrutura de pastas — app/

**Status**: done
**Arquivos tocados**: nenhum

## Resumo

Projeto Flutter em `app/`. As 5 camadas estão criadas em `lib/` (config, data, domain, routing, ui), cada uma com seu próprio `CLAUDE.md`. Nenhum arquivo `.dart` de implementação existe ainda — apenas `lib/main.dart` e os `CLAUDE.md` de cada camada.

## Árvore (3 níveis, sem build/.dart_tool/Pods)

```
app/
├── CLAUDE.md
├── analysis_options.yaml
├── pubspec.yaml / pubspec.lock
├── android/
│   └── app/src/...
├── ios/
│   ├── Flutter/
│   └── Runner/  (AppDelegate.swift, SceneDelegate.swift, Info.plist)
├── lib/
│   ├── main.dart
│   ├── config/   CLAUDE.md — vazio
│   ├── data/     CLAUDE.md — vazio
│   ├── domain/   CLAUDE.md — vazio
│   ├── routing/  CLAUDE.md — vazio
│   └── ui/       CLAUDE.md — vazio
└── test/
    └── widget_test.dart
```

## Notas pro orquestrador

- Nenhuma dependência extra instalada além do scaffold padrão Flutter (verificar `pubspec.yaml` se precisar confirmar).
- `lib/` está 100% vazio de implementação — scaffolding pronto para receber código.
