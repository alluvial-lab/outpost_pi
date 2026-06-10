# 42 — Cockpit: Worktrees por workspace

## Contexto

O Cockpit (plano 37) tem hoje uma lista **plana** de workspaces no rail esquerdo
— cada workspace é um `Project` (`cockpit/lib/domain/entities/project.dart`:
`id`/`name`/`path`/`colorValue`), persistido em Hive
(`hive_project_repository.dart`), com sua própria árvore de panes
(`CockpitViewModel._trees: Map<projectId, PaneNode>`) e um `_GitBadge`
read-only (`projects_rail.dart`) que mostra `branch + dirtyCount` via
`GitStatusReader` (`git rev-parse` / `git status --porcelain`).

Esta feature adiciona **worktrees**: a partir de um workspace com git, o usuário
cria *features* paralelas, cada uma com sua própria pasta de checkout
(`git worktree`) e branch nova. Cada worktree aparece como um **fork pendurado
abaixo do workspace** no rail, e ao clicar abre a pane normalmente — só que
apontando pro diretório do worktree. É o caminho natural pra rodar N features em
paralelo, cada uma com seu(s) agente(s) `pi --mode rpc`.

Mockup de referência (rail): workspaces com avatar + badge de notificação +
chip de branch; abaixo de cada um, forks com ícone de branch + nome + badge de
dirtyCount (ou ponto cinza quando limpo).

### Relação com o plano 37

- **Reusa a máquina existente do Cockpit**: um worktree é um `Project` de 1ª
  classe (com `parentId`), então `selectProject`, `_trees`, restauração de panes
  e `_GitBadge` valem de graça. A feature é majoritariamente **`domain` + `data`
  (git) + rail (`ui`)** — não inventa uma 2ª arquitetura.
- **Local-only (decisão B do plano 37)**: nada de relay/mesh aqui. Worktree é só
  pasta + processo local. Reachability remota de agentes de worktree é a mesma
  evolução futura do plano 37 (carregar a extensão no spawn) — fora de escopo.
- **Git já está fiado, mas read-only**. Este plano adiciona o lado **mutável** do
  git (worktree add/remove, branch -D) num contrato próprio, sem misturar com o
  `GitStatusReader` de leitura.

## Decisões fechadas (entrevista 2026-06-09)

| # | Tema | Decisão |
|---|---|---|
| **1** | Modelo de dados | Worktree = `Project` de 1ª classe com `parentId`. Reusa `selectProject`/`_trees`/`GitBadge`/restauração de panes. Diferença é só visual (fork) + cwd/branch apontam pro worktree |
| **2** | Local no disco | **Dentro do workspace**: `<workspace>/.pi/remote/worktrees/<nome>` |
| **3** | Base da branch | Branch **nova** a partir do **HEAD atual do pai**: `git worktree add <path> -b <nome>` (sem ref explícito) |
| **4** | Fonte da verdade | **Git manda**. Existência vem de `git worktree list` + checagem de pasta; reconcilia e reflete someço externo. Hive guarda só metadata de UI por path |
| **5** | Escopo dos forks | **Espelho fiel**: toda worktree do `git worktree list` vira fork (não só as de `.pi/`), exceto a entrada raiz (que É o `Project` pai) |
| **6** | Remoção | `git worktree remove` **+** `git branch -D <nome>` **sempre** (nessa ordem: remove worktree antes de apagar branch), com confirmação forte + aviso se branch não-mergeada |
| **7** | `.pi/` ignore | **Assumir que já está gitignored**. Sem auto-ignore. Fragilidade documentada (ver Riscos) |
| **8** | Badge do fork | **dirtyCount** do worktree (`git status --porcelain` por path); ponto cinza = limpo (0) |
| **9** | Agente órfão | Remoção (menu) **ou** someço externo com agente vivo → **mata os `pi` + fecha panes + seleção volta pro pai** |
| **10** | Rigor da validação | Valida **ref completo** (equivalente a `git check-ref-format --branch`): sem espaço, sem `..` `~^:?*[\`, não começa com `-`/`.`, não termina em `.lock`/`/`. Barra liberada. Criar só acende no que o git aceita |
| **11** | Escopo da unicidade | Único vs **branches locais (`git branch`) + worktrees existentes (`git worktree list`)**. Ignora remotas |
| **12** | Expandir forks | **Sempre expandido** (sem chevron), fiel ao mockup |
| **13** | Criar a partir de | "Criar worktree" **só no workspace pai**. Forks têm menu só com "Remover". Lista plana, 1 nível |
| **14** | Pós-criar | **Auto-seleciona** o fork + pane vazia pronta (igual abrir workspace novo) |
| **15** | Nome no disco | **Espelha a branch (aninha)**: `feat/sso` → `.pi/remote/worktrees/feat/sso` (subpasta real, sem colisão) |
| **16** | Notif do fork | Fork tem **sinal próprio** de "agente terminou não-visto", além do dirtyCount |
| **17** | Liveness | Reconcilia **nos ganchos atuais** (init / select do pai / fim de turno). Mudança externa aparece no próximo select. Sem polling/watcher |
| **18** | Hive do fork | Persiste **só layout de panes/sessões** por path (restaurar agentes/tabs). Notificação é efêmera; nome vem da branch; dirtyCount do git |
| **19** | Visual dos 2 sinais | **Dot de notif sobreposto ao badge git**: mantém o badge dirtyCount do mockup; agente-terminou vira dot colorido no canto (ou o ponto cinza limpo vira azul) |
| **20** | Ordem dos forks | **Ordem do `git worktree list`** (≈ criação) |
| **21** | Durante criar | **Dialog trava com spinner**; erro → inline no dialog; sucesso → fecha + auto-seleciona |

## Estrutura esperada (camadas tocadas)

Segue a regra de ouro do `cockpit/` (ui → domain ← data; config injeta). O lado
**mutável** do git é contrato novo em `domain/contracts/`, implementado em
`data/`, sem tocar o `GitStatusReader` de leitura.

```
cockpit/lib/
├── domain/
│   ├── entities/project.dart            ← + `parentId: String?` (null = workspace raiz)
│   └── contracts/worktree_manager.dart  ← NOVO: list / add / remove (+ validação de nome)
├── data/
│   └── filesystem/worktree_manager_impl.dart ← NOVO: roda `git worktree add|list|remove`,
│                                               `git branch -D`, `check-ref-format`; reusa a
│                                               infra de resolução do binário git do
│                                               `git_status_reader_impl.dart`
└── ui/cockpit/
    ├── viewmodels/cockpit_viewmodel.dart ← reconciliação de worktrees por pai, kill-on-remove,
    │                                        dirtyCount por fork, reusa selectProject(forkId)
    └── widgets/
        ├── projects_rail.dart            ← renderiza forks sob o pai (badge + dot de notif),
        │                                    item "Criar worktree" no menu do pai, menu "Remover"
        │                                    no fork
        └── worktree_create_dialog.dart   ← NOVO: campo + validação ao vivo + spinner
```

> **Worktree ≠ entidade persistida.** O `Project`-fork existe em runtime
> (derivado de `git worktree list`), mas no Hive só mora o **layout de panes**
> chaveado pelo path (decisão 18). A `ProjectRepository` continua guardando só os
> workspaces raiz; os forks são reconstruídos do git a cada ativação do pai.

## Waves (com critério de aceite)

### Wave 1 — Git mutável + validação (`domain` + `data`)

- `WorktreeManager` (contrato) + impl: `list(repoPath)` (parseia
  `git worktree list --porcelain`, exclui a raiz), `add(repoPath, name)`
  (`git worktree add .pi/remote/worktrees/<name> -b <name>`),
  `remove(repoPath, worktreePath, branch)` (`git worktree remove` **depois**
  `git branch -D`), `validateName(repoPath, name)` (check-ref-format + unicidade
  vs branches locais + worktrees).
- `dirtyCount` por worktree reusa `GitStatusReader.read(worktreePath)`.

*Aceite:* testes de `validateName` (espaço, `..`, `.lock`, barra-ok, colisão com
branch/worktree existente); `add`/`list`/`remove` validados num repo temporário
(`flutter test`); `flutter analyze` zero issues.

### Wave 2 — Rail: forks espelhados do git

- `Project` ganha `parentId`. `CockpitViewModel` reconcilia os forks de cada
  workspace via `WorktreeManager.list` nos ganchos existentes (decisão 17) e
  expõe a lista ordenada (decisão 20) pro rail.
- `projects_rail.dart` renderiza os forks sempre expandidos (decisão 12), 1 nível
  (decisão 13): ícone de branch + nome (= branch) + badge dirtyCount (ponto cinza
  = limpo) com dot de notif sobreposto (decisão 19).
- Clicar num fork = `selectProject(forkId)` → centro mostra a árvore de panes do
  fork apontando pro path do worktree.

*Aceite:* criar uma worktree no terminal → ela aparece como fork ao selecionar o
pai; clicar no fork abre pane no cwd do worktree; editar arquivo no worktree →
badge reflete dirtyCount no próximo refresh; `git worktree remove` por fora → fork
some ao reselecionar o pai.

### Wave 3 — Fluxo de criar

- Item "Criar worktree" no menu (⋮) do **workspace pai apenas**, habilitado só se
  há git na raiz (`gitInfo(projectId) != null`).
- `worktree_create_dialog.dart`: campo de nome com validação ao vivo (decisão 10/11);
  botão Criar acende só quando válido; ao confirmar, **trava com spinner** (decisão
  21), erro inline; sucesso → fecha, fork **auto-selecionado** com pane vazia
  (decisão 14).

*Aceite:* digitar nome inválido (espaço/`..`/duplicado) mantém Criar apagado com
motivo visível; nome válido cria a worktree em `.pi/remote/worktrees/<nome>` na
branch nova a partir do HEAD do pai; o app cai dentro do fork novo com pane vazia.

### Wave 4 — Remover + ciclo de vida

- Menu "Remover" no fork: confirmação forte + aviso se branch não-mergeada →
  `git worktree remove` + `git branch -D` (decisão 6).
- Kill-on-remove (decisão 9): mata os `pi` do fork, fecha panes, seleção volta pro
  pai. Mesma rotina disparada quando a reconciliação detecta pasta morta (someço
  externo).

*Aceite:* remover um fork com agente vivo → processo morto (`pgrep` limpo), panes
fechadas, pai selecionado, pasta e branch sumiram do git; apagar a pasta por fora
→ no próximo select do pai o fork some e o agente órfão é encerrado.

## DoD

- [x] 1 — `WorktreeManager` (contrato + impl) com `list`/`namespace`/`add`/
      `remove`; `WorktreeNameValidator` puro (git-ref rules + unicidade) em
      `domain/validators/`; binding na DI; dirtyCount por fork reusa
      `GitStatusReader`. **14 testes verdes + `analyze` zero issues** (validador
      puro + impl contra repo git temporário)
- [~] 2 — `Project.parentId`; reconciliação de forks no `CockpitViewModel`
      (`_refreshWorktrees` nos ganchos init/select/fim-de-turno; fork sumido →
      kill+close+volta pro pai); rail consome `rootProjects` + `worktreesOf`,
      renderiza forks (conector em L, badge dirtyCount + dot de notif, sempre
      expandido, ordem do git); clicar fork = `selectProject` no cwd do worktree;
      IndexedStack/`_activeIndex` incluem forks. **Código done + `analyze`/`test`
      (41)/`build macos` verdes**; falta **aceite visual** (`flutter run -d macos`,
      criar worktree no terminal → ver o fork — não automatizável headless)
- [~] 3 — Item "Criar worktree" no menu do pai (gated em `gitInfo != null`);
      `worktree_create_dialog.dart` com validação ao vivo via `WorktreeNameValidator`
      (mensagem por causa) + Criar gated + **spinner durante o `add`** + erro git
      inline; `createWorktree`/`worktreeNamespace` no VM; sucesso → auto-select do
      fork com pane vazia. **Código done + `analyze`/`test`/`build macos` verdes**;
      falta **aceite visual** (criar pela UI e cair no fork — não headless)
- [x] 4 — "Remover" no fork (`worktree remove` + `branch -D`, confirmação +
      aviso não-mergeada); kill-on-remove e na detecção de someço externo
      — *implementado 2026-06-09: `removeWorktree`/`isWorktreeBranchMerged` no VM
      (reusam `_refreshWorktrees` → rotina única de kill+close+volta-pro-pai);
      menu ⋮ "Remover" no fork (`_ForkMenuButton`); `_removeWorktree` na page com
      `showConfirmDialog` + aviso de não-mergeada (via `isBranchMerged`) + erro git
      via `showInfoDialog`. **Achei e corrigi 2 bugs latentes**: `isBranchMerged`
      estava no contrato mas NÃO no impl (projeto não compilava); e o comando
      `git branch --merged --format=…` era malformado (`--merged` engole o
      `--format`) → reescrito pra parsear o output plano. `analyze` 0 · **42/42
      testes** (+1 de `isBranchMerged`) · `build macos` ✓. Falta só aceite visual
      (Wave 5).*
- [ ] 5 — Aceite visual do usuário (`flutter run -d macos`): criar/usar/remover
      worktree e ver os forks no rail (não automatizável headless)

## Refinamentos pós-teste visual (2026-06-10)

Levantados no aceite (a funcionalidade-base passou: criar/usar/remover/someço-externo).

- **Tooltip no fork** — `_WorktreeItem` em `Tooltip` (branch + path) no hover.
- **Tooltip no workspace** — `_ProjectItem` em `Tooltip` (nome + path), igual ao fork.
- **Drag-drop pro input não perde mais o foco** — o composer (`agent_composer.dart`)
  ganhou `_restoreInputFocus()` (requestFocus pós-frame) chamado nos dois caminhos de
  drop (`DropTarget.onDragDone` do SO + `DragTarget<String>.onAcceptWithDetails` do
  painel Files) — o drag roubava o foco do `TextField` e não devolvia.
- **Linha de árvore fiel ao mockup** — `_ForkLinePainter` (substitui o `_ElbowPainter`
  por-fork): vertical **contínua** nos forks do meio, **"└"** no último (via `isLast`),
  **fora** do realce do item, preenchendo a altura (`IntrinsicHeight`+`stretch`) pra a
  espinha emendar. *Geometria (x=20, indent 30) ajustada no olho — sujeita a nudge.*
- **Título `workspace · worktree` no topbar** — `vm.selectedDisplayTitle` compõe
  `"<workspace> · <fork>"` com middle-dot `·` (U+00B7) quando um fork está selecionado.
- **File watcher (refresh ao vivo da aba de arquivo)** — *na verdade mais amplo que
  worktrees*: o viewer lia o arquivo uma vez (`FileViewerSession.view` imutável) e
  congelava. Agora `FileReader.watch(path)` (contrato + impl `File.watch`) alimenta a
  VM, que relê e atualiza o `view` in-place (debounce 120ms, cleanup no
  `_disposeSession`/`dispose`). `FileViewerSession.view` virou mutável.
- **#5 — auto-deletar worktree ao mergear: DECIDIDO NÃO fazer (por ora).** Detecção
  via `git branch --merged` é parcial (squash/rebase-merge não marcam → falha no fluxo
  GitHub comum) e auto-`branch -D` joga fora a confirmação da decisão 6 (risco de perda
  silenciosa). Alternativa futura de baixo risco: **selo "mergeada — pode remover"** no
  fork (reusa `isBranchMerged`), 1-clique com a confirmação normal. Fica como evolução.

## Riscos / Trade-offs explícitos

- **`.pi/` precisa estar gitignored (decisão 7).** Em repo que não ignora `.pi/`,
  a 1ª worktree aninhada estoura o `dirtyCount` do pai (`main 3` → enorme). Sem
  auto-ignore neste plano; fragilidade conhecida. Mitigação futura possível:
  `.git/info/exclude` automático.
- **N chamadas `git status` por refresh** (uma por fork, decisão 8). Em repo com
  muitos worktrees o fan-out cresce; aceitável no MVP, batch é otimização futura.
- **Reconciliação lazy (decisão 17).** Worktree criado/apagado no terminal só
  reflete no próximo select do pai — não é tempo-real. Trade por custo zero ocioso.
- **Someço externo mata agente vivo sem perguntar (decisão 9).** Escolha
  consciente: pasta morta → encerra os `pi` órfãos na reconciliação.
- **"Remover" apaga a branch sempre (decisão 6).** Como espelhamos worktrees
  externas (decisão 5), o `branch -D` também atinge branch criada na mão — daí a
  confirmação forte + aviso de não-mergeada.

## Não-objetivos

- **Aninhamento real / worktree-de-worktree** (decisão 13 → lista plana 1 nível).
- **Criar worktree a partir de um fork** (decisão 13 → só no pai).
- **Recolher forks** (decisão 12 → sempre expandido).
- **Checar branches remotas na unicidade** (decisão 11 → só locais + worktrees).
- **Auto-`.gitignore`** (decisão 7 → assumir ignorado).
- **Polling / file-watcher** pra liveness (decisão 17 → ganchos atuais).
- **Reachability remota de agentes de worktree** — herda o local-only do plano 37
  (decisão B); evolui junto com "carregar a extensão no spawn".

## Próximos planos / evolução

- **Recolher forks + contagem no pai** se o rail ficar denso com muitos worktrees
  (revisita a decisão 12).
- **Liveness reativa** (file-watcher de `.git/worktrees/`) se a reconciliação lazy
  incomodar (revisita a decisão 17).
- **`.pi/` ignore automático** via `.git/info/exclude` (mitiga o risco da decisão 7).
- **Promover worktree a daemon / reachability remota** — converge com a evolução
  do plano 37 (extensão no spawn → fork alcançável do celular).
