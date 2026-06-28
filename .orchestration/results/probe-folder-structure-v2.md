# [ORCH:probe-folder-structure-v2] Estrutura de pastas — app/

**Status**: done
**Arquivos tocados**: nenhum

## Resumo

Scaffold Flutter padrão com `lib/` dividido nas 5 camadas arquiteturais (config, data, domain, routing, ui) — todas vazias de implementação exceto `lib/main.dart`.

## Árvore

```
app/
├── CLAUDE.md
├── analysis_options.yaml
├── pubspec.yaml
├── pubspec.lock
├── android/
│   ├── app/
│   │   └── src/
│   ├── gradle/
│   ├── build.gradle.kts
│   └── settings.gradle.kts
├── ios/
│   ├── Flutter/
│   ├── Runner/
│   │   ├── AppDelegate.swift
│   │   ├── SceneDelegate.swift
│   │   └── Info.plist
│   ├── Runner.xcodeproj/
│   └── Runner.xcworkspace/
├── lib/
│   ├── main.dart
│   ├── config/    (CLAUDE.md)
│   ├── data/      (CLAUDE.md)
│   ├── domain/    (CLAUDE.md)
│   ├── routing/   (CLAUDE.md)
│   └── ui/        (CLAUDE.md)
└── test/
    └── widget_test.dart
```

`lib/` tem 5 camadas criadas com CLAUDE.md próprio, sem nenhum arquivo de implementação ainda.
