# Camada `data/`

## Propósito

Traduzir contratos de `domain/` em chamadas para o mundo bagunçado de I/O — aqui,
**processos** (`pi --mode rpc`) e o **filesystem**. Esta camada é a fronteira
entre regras de negócio puras e os subprocessos/arquivos reais.

É a camada que mais difere do `app/`: lá ela falava com rede/mesh/crypto; aqui ela
**spawna e dirige child processes** e **lê a árvore de arquivos** (read-only).

## Deve fazer

1. **Implementar contratos do domínio** — cada interface de
   `domain/contracts/` ou `domain/repositories/` tem sua implementação concreta
   aqui (`RpcProcessGateway` → `RpcProcessService`, `FileSystemGateway` →
   `FileSystemService`).
2. **Gerenciar o ciclo de vida do processo RPC** — `Process.start("pi", ["--mode",
   "rpc", ...], workingDirectory: cwd)`; manter `stdin` para enviar comandos,
   ouvir `stdout` para o stream de eventos, escutar `exit` para detectar crash.
   **Matar o processo limpo no dispose (sem órfão)** é responsabilidade desta camada.
3. **Traduzir o wire format** — adapters convertem a linha JSON crua do stdout
   (`{type, command/event, ...}`, schema do Pi SDK — ver `plan/37`) em `RpcEvent`
   tipado do domínio, e o `sendUserMessage` do domínio em linha JSON no stdin.
   **A `ui/` nunca vê `Map<String,dynamic>` cru.**
4. **Ler o filesystem read-only** — montar a `FileNode` tree de um `Project`,
   ler conteúdo de arquivo para o viewer. **Nunca escrever** (o agente edita, o
   Cockpit observa).
5. **Propagar falhas contextualizadas** — capturar erros técnicos (spawn falhou,
   binário `pi` não encontrado, stdout fechou, arquivo ilegível) e convertê-los
   em erros compreensíveis pelo domínio:

   ```dart
   try {
     // spawn / IO
   } catch (e, s) {
     return Failure(
       AppException.fatal('Falha ao iniciar o agente.', stackTrace: s, originalError: e),
     );
   }
   ```

## Não deve fazer

1. **Implementar regras de negócio** — decisões de domínio (1 agente por pasta,
   validação de pasta) permanecem em `domain/`.
2. **Consumir UI** — nenhum import de `ui/`, `widget`, `BuildContext`.
3. **Vazar o wire format pra cima** — o shape das linhas JSON do RPC fica
   encapsulado aqui; o domínio e a UI só veem `RpcEvent`.
4. **Escrever no filesystem do projeto** — leitura apenas.
5. **Acessar `auto_injector` direto** fora do setup — instâncias vêm de `config/`.

## Estrutura sugerida

```
data/
├── rpc/             # RpcProcessService: Process.start, stdin/stdout, exit/crash
├── adapters/        # parse JSON-line ↔ RpcEvent; comando domínio → stdin
├── filesystem/      # FileSystemService: árvore + leitura read-only de arquivo
└── repositories/    # implementações dos contratos do domínio
```

## Vocabulário

- **RpcProcessService** — dono do `Process` do `pi --mode rpc`: spawn, write no
  stdin, stream do stdout, detecção de crash, kill.
- **Adapter / Mapper** — converte linha JSON crua ↔ `RpcEvent`/comando do domínio.
- **FileSystemService** — leitura read-only da árvore e do conteúdo de arquivos.
- **Repository** — implementação concreta que satisfaz um contrato do domínio
  combinando os serviços acima.
