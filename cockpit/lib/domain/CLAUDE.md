# Camada `domain/`

## Propósito

Materializar o conhecimento do negócio do Cockpit. Aqui vivem modelos, casos de
uso e validadores com regras determinísticas, **independentes de UI, processo ou
filesystem**. Esta camada é o núcleo — todas as outras dependem dela; ela não
depende de nenhuma.

No Cockpit, o "negócio" é: **projetos**, **agentes** (`pi --mode rpc`), o **stream
de eventos RPC** e a **árvore de arquivos**. As entidades modelam esses conceitos
sem saber *como* um processo é spawnado ou *como* o stdout é lido — isso é `data/`.

## Deve fazer

1. **Modelar entidades e value objects** com imutabilidade e igualdade
   consistente (`==` / `hashCode`): `Project`, `Agent`, `AgentStatus`,
   `RpcEvent` (deltas de texto, tool_call, tool_result, agent_end), `FileNode`.
2. **Orquestrar regras via Use Cases**: cada `*UseCase` expõe um único verbo do
   domínio (`SpawnAgentUseCase`, `SendPromptUseCase`, `KillAgentUseCase`,
   `ListProjectFilesUseCase`) e delega integrações aos contratos.
3. **Validar invariantes** em `validators/`, lançando exceções tipadas (ex.:
   pasta inexistente, agente já vivo na mesma pasta).
4. **Manter pureza**: código síncrono ou assíncrono previsível, sem side effects
   além de chamadas a contratos. O `Stream<RpcEvent>` é exposto como contrato;
   a implementação (parse do stdout) mora em `data/`.
5. **Expor contratos**: interfaces de baixo nível em `contracts/` (ex.:
   `RpcProcessGateway`, `FileSystemGateway`) e de repositório em `repositories/`.
   Implementações concretas vivem em `data/`.

## Não deve fazer

1. **Importar Flutter** — nada de `BuildContext`, widgets, `Material`. Use Dart puro.
2. **Acessar infraestrutura diretamente** — `dart:io` `Process`, leitura de
   arquivos, parse de stdout pertencem a `data/`. O domínio só conhece os
   contratos.
3. **Guardar estado mutável global** — evite singletons; objetos vêm pelo injector.
4. **Conhecer o wire format do RPC** — o shape das linhas JSON do `pi --mode rpc`
   é detalhe de transporte (`data/`). O domínio vê `RpcEvent` já tipado.
5. **Duplicar lógica** — reutilize validators e models existentes.

## Estrutura sugerida

```
domain/
├── entities/           # Project, Agent, RpcEvent, FileNode (id + ciclo de vida)
├── value_objects/      # AgentStatus, FilePath, ...
├── contracts/          # interfaces de baixo nível (RpcProcessGateway, FileSystemGateway)
├── repositories/       # interfaces de repositório (AgentRepository, ...)
├── usecases/           # operações unitárias (spawn, send, kill, list files)
├── validators/         # invariantes (pasta válida, 1 agente por pasta, ...)
└── exceptions/         # exceções tipadas do domínio
```

## Vocabulário

- **Project** — uma pasta que o usuário abriu no Cockpit.
- **Agent** — uma instância de `pi --mode rpc` ligada a um Project, com ciclo de
  vida próprio (`booting` → `ready` → `streaming` → `crashed`/`stopped`).
- **RpcEvent** — evento tipado emitido pelo agente (delta de texto, tool_call,
  tool_result, agent_end) — a versão de domínio do stream do stdout.
- **Use Case** — operação unitária do domínio exposta à aplicação (1 verbo).
- **Gateway/Contrato** — interface declarada no domínio e implementada em `data/`
  (ex.: `RpcProcessGateway` esconde o `Process.start`).
- **Invariante** — regra que sempre precisa ser verdadeira (ex.: a mesma pasta
  não roda dois agentes do Cockpit ao mesmo tempo).
