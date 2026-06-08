# 40 — Suporte Windows: supervisor + mesh local (socket cross-platform)

## Contexto

`remote-pi install` / `uninstall` / `restart-supervisor` (plano 26) só funcionam em
POSIX (launchd/systemd). Levar o supervisor pro **Windows** esbarra num
pré-requisito mais profundo: o **IPC local por socket** não funciona como está no
Windows — e isso afeta **também a mesh local**, não só o control-plane do
supervisor.

> **Origem**: handoff do pane `Extension`
> (`.orchestration/results/handoff-windows-supervisor.md`, 2026-06-08). Análise +
> decisões **fechadas com o usuário**. Implementação fica no pane `Extension`.

### Diagnóstico-chave (confirmado no código)

O Node, no Windows, implementa IPC local como **named pipe** (`\\.\pipe\nome`),
**não** como socket de arquivo. Hoje usamos **paths `*.sock`** em dois lugares:

- **Supervisor control-plane**: `~/.pi/remote/supervisor.sock`
- **Broker da mesh local**: `~/.pi/remote/sessions/<n>/broker.sock` — hardcoded em
  `mesh_server.ts:49` (`join(homedir(), ".pi", "remote", "sessions", "local",
  "broker.sock")`).

Passar um path de arquivo pro `listen()` no Windows não funciona. **A mesh precisa
do fix também**: entrar na mesh passa por `MeshNode.connect → SessionPeer.start →
joinOrLead(brokerSock)` **antes** da ponte do relay — sem o broker local subir, o
agente não entra nem na mesh local nem na cross-PC.

> **Cross-PC (relay/WebSocket) NÃO muda** — `ws`/WSS é TCP, cross-platform.
> Envelope, roteamento, ACK, addressing `<pc>:<peer>`, `broker_remote`/
> `peer_inventory`: zero alteração. **Cron (plano 39) também não muda** — croner
> (timers JS), `cron.json`/`cron.jsonl` (fs puro), `fireJob` via stdio; só depende
> do supervisor rodar.

A correção é **trocar a STRING do endereço por plataforma** (mesma API `net`) +
ajustar o ciclo de vida (o pipe some sozinho quando o dono morre → sem
`existsSync`/`unlink` de stale; usar **connect-probe**).

### Relação com planos existentes

- **Plano 26 (daemon/supervisor)** — adiciona o 3º backend de serviço (Task
  Scheduler) ao lado de launchd/systemd; o padrão `service-templates/` já existe
  (`launchd.plist.template`, `systemd.service.template`).
- **Planos 19/25/34 (mesh)** — o Bloco A conserta o `broker.sock`, então a **mesh
  local passa a subir no Windows** de graça (cross-PC já era TCP).
- **Plano 39 (cron)** — roda em cima de A+B+C, **sem alteração de código**.

## Decisões fechadas (2026-06-08)

| # | Decisão | Valor | Por quê |
|---|---|---|---|
| **A** | Backend de serviço Windows | **Task Scheduler (`schtasks`)** — user-level, sem admin, com `<RestartOnFailure>` | Paridade com KeepAlive (launchd) / `Restart=always` (systemd) sem exigir privilégio de admin |
| **B** | IPC Windows | **Named pipe** `\\.\pipe\remote-pi-*-<user>` (per-user) — mesma API `net`; connect-probe no lifecycle | Pipe é **machine-global** → embutir o usuário evita colisão multi-user; pipe auto-limpa no exit do dono → não há stale pra `unlink` |
| **C** | Spawn do `pi` no Windows | **Resolver o caminho do `pi.cmd`** (ex.: `where pi`) em vez de `shell:true` | `spawn("pi")` dá `ENOENT` no Windows (é `pi.cmd`); resolver o path evita injeção de shell |

## Blocos (sequenciados — A → B → C)

> **Ordem importa**: sem A, instalar o serviço não adianta (CLI/Cockpit não
> alcançam o supervisor, e a mesh nem sobe). B sozinho sem A = supervisor fantasma.

### Bloco A — Socket local cross-platform (FUNDAÇÃO: `supervisor.sock` + `broker.sock`)

Resolvedor de endereço por plataforma + lifecycle pipe-aware. Cobre os **dois**
sockets de uma vez.

- `src/session/global_config.ts` — `sessionSockPath()` (pipe no win32) +
  `sessionHasSock()` → **connect-probe** (não `existsSync`).
- `src/session/leader_election.ts` — `joinOrLead`/`ensureCleanSock`: **pular
  `unlink`/`existsSync` no Windows** (pipe auto-limpa); o connect-probe já existe.
- `src/daemon/supervisor.ts` — `supervisorSockPath()` → pipe no win32;
  `_bindUds`/`_probeSupervisor` pipe-aware.
- `src/mcp/mesh_server.ts` (`:49`) **e** `src/index.ts` — onde o `BROKER_SOCK` é
  montado hardcoded → usar o resolvedor.
- Nome de pipe **per-user** (embutir o usuário).

*Aceite*: no **POSIX, comportamento idêntico** (suíte atual verde); o resolvedor
retorna `\\.\pipe\…` no win32; o lifecycle **não chama `unlink` no win32**; testes
do resolvedor por plataforma (injetando `platform`).

### Bloco B — Spawn do `pi` no Windows (`src/daemon/rpc_child.ts`)

`spawn("pi", …)` no Windows dá `ENOENT` (é `pi.cmd`). Resolver o caminho do
`pi`/`pi.cmd` (decisão C — preferir resolução de path a `shell:true`).

*Aceite*: daemon sobe no Windows; nos POSIX nada muda.

### Bloco C — Backend de serviço Windows (`src/daemon/install.ts` + `index.ts`)

- `detectPlatform()` → `"windows"`.
- Novo `service-templates/task-scheduler.xml.template` (Exec = `{NODE}
  {SUPERVISOR}`, `ONLOGON`, `RestartOnFailure`) + `findTemplate("taskscheduler")`.
- `installService`: `schtasks /Create /XML <file> /TN RemotePiSupervisor /F` +
  `schtasks /Run`.
- `uninstallService`: `schtasks /End` + `schtasks /Delete /F`.
- `_restartSupervisorCommand` (em `index.ts`): win32 → `schtasks /End` + `/Run`
  (hoje retorna `null` → exit 1).
- `linkCliBinaries`: **pular no Windows** (symlink/`~/.local/bin` são POSIX; no
  Windows o `npm i -g` já dá shims `.cmd`).

*Aceite*: `remote-pi install` registra+inicia a task; `uninstall` remove;
`restart-supervisor` reinicia (exit 0/≠0 corretos); o comando aparece no help.

### Cron — NENHUMA mudança

croner (timers JS, tz via ICU), `cron.json`/`cron.jsonl` (fs puro), scheduler
in-process, `fireJob` via `child.stdin` (stdio). Roda assim que A+B+C estiverem
prontos. **Validar** rodando 1 job num Windows real.

## DoD

> **Implementado + commitado em `e6e2753`** (2026-06-08; só `pi-extension/`). POSIX
> sem regressão: `tsc` limpo, `pnpm test` **507/507**; ramos win32 por testes
> platform-injected. **Smoke real em Windows PENDENTE** (5 itens: pipe bind/connect,
> `schtasks` create/run/end/delete, `pi.cmd` via `where`, cron 1 job, encoding do
> XML UTF-8 vs UTF-16) — exige máquina/CI Windows; **não declarar "Windows ok"** sem
> isso. Detalhes em `.orchestration/results/40-windows-supervisor.md`.

- [x] **Bloco A** — resolvedor de socket por plataforma (`supervisor.sock` +
      `broker.sock`, via novo `ipc.ts`) + lifecycle pipe-aware; testes por
      plataforma; **POSIX sem regressão** (507/507)
- [x] **Bloco B** — `pi`/`pi.cmd` resolvido no Windows (`resolvePiBin` via `where`)
- [x] **Bloco C** — `install`/`uninstall`/`restart-supervisor` no Windows via
      `schtasks` (template `task-scheduler.xml`); `linkCli` pulado no Windows
- [ ] **Cron** — roda no Windows sem alteração de código (código cross-platform
      confirmado; **smoke ponta-a-ponta de 1 job ainda PENDENTE** — comentado na CI,
      precisa do `pi` + provider/secret; o resto da validação Windows já corre na CI)
- [x] `tsc` + `pnpm test` (507/507) verdes; `pnpm build`

## Riscos / notas

- **Validação real exige Windows**: o dev host é macOS. Os testes **injetam
  `platform`** pra exercitar os ramos Windows, mas o smoke real (pipe, schtasks,
  spawn de `pi.cmd`) precisa de **máquina/CI Windows** — avaliar um runner Windows
  no CI. Não declarar "Windows ok" só com testes platform-injected.
- **Named pipe é machine-global** → o usuário embutido no nome evita colisão
  multi-user no mesmo host.
- **Testes que isolam via `REMOTE_PI_HOME`** (path de arquivo): no Windows o pipe
  **não mora** sob `REMOTE_PI_HOME` → o helper de path precisa de **sufixo único
  por teste** pra rodar em paralelo sem colidir no nome do pipe.
- **Sem dep nova** — tudo com `net` / `child_process` / `schtasks` nativos.

## Próximos planos / evolução

- **Runner Windows no CI** — ✅ **criado**: `.github/workflows/windows-pi-extension.yml`
  (`windows-11-arm` + `windows-latest`). Roda a suíte em Windows real (ARM+x64) +
  smoke de `schtasks` (valida XML) + smoke de named-pipe (best-effort). **Roda no
  GitHub só após push.** Falta o smoke do cron ponta-a-ponta (comentado no
  workflow — precisa do `pi` global + provider via secret).
- **Paridade de install no Cockpit** — se o Cockpit (plano 37) passar a oferecer
  "instalar supervisor" pela UI, o backend Windows daqui é reusado.
