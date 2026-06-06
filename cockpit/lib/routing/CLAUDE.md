# Camada `routing/`

## Propósito

Descrever e coordenar as rotas do aplicativo, conectando paths a páginas/flows sem
infiltrar lógica de UI ou domínio. Esta camada sustenta o `GoRouter`, define
guardas e garante consistência entre rotas declaradas e a navegação real.

> No MVP do Cockpit a navegação é mínima (essencialmente o shell único de layout —
> ver plano 37). Mesmo assim, a composição de ViewModels passa por aqui desde o
> início, para não nascer dívida quando as features crescerem.

## Deve fazer

1. **Centralizar paths** — manter constantes (`routePaths`) para evitar strings
   mágicas e facilitar refactors.
2. **Definir topologia de navegação** — rotas, shells e redirecionamentos vivem aqui.
3. **Delegar construção de páginas** — cada rota instancia apenas o widget raiz
   correspondente; a feature em `ui/` cuida do conteúdo.
4. **Aplicar middlewares/guards** — checagens encapsuladas em `redirect`/guards.
5. **Injetar ViewModels na árvore** — a composição de `MultiProvider` e
   `ViewmodelProvider`s acontece **exclusivamente** em `routing/router.dart`,
   garantindo um único ponto de orquestração por rota.

## Não deve fazer

1. **Acessar serviços diretamente** — lógica de negócio fica no domínio; a UI
   consome via ViewModels.
2. **Criar side effects globais** — nada de spawn de processo ou inicializações
   aqui; apenas navegação.
3. **Duplicar rotas em features** — qualquer ajuste de path passa por `routing/`.
4. **Misturar responsabilidades** — sem widgets inline ou lógica de feature.

## Estrutura sugerida

```
routing/
├── router.dart          # GoRouter + MultiProvider/ViewmodelProvider
├── routes.dart          # constantes de path (routePaths.shell, ...)
└── guards.dart          # redirect logic (quando necessário)
```

## Vocabulário

- **Route Path** — string declarada em `routes.dart` que identifica uma navegação.
- **Shell Route** — estrutura que guarda o layout persistente (no Cockpit, o
  shell de 3 colunas: projetos | centro | arquivos).
- **Entry Widget** — widget superior de uma feature responsável por providers e
  wrappers.
