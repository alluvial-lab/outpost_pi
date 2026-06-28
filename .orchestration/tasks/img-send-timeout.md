Bug em produção: ao enviar imagem, o balão fica "sending…" pra sempre quando o
echo não volta. (A causa-raiz principal está sendo corrigida no RELAY em
paralelo; esta tarefa é a REDE DE SEGURANÇA no app.)

Comportamento desejado (decisão do usuário): timeout de **20 segundos** por
mensagem enviada; se o echo não chegar, **remover o balão silenciosamente** —
NÃO mostrar estado "failed", NÃO deixar spinner. O balão some e segue a vida.

Arquivo principal: `lib/data/sync/sync_service.dart`. Camada `data/` — siga o
CLAUDE.md da camada (sem `context`, sem UI, tipado).

Contexto técnico (já investigado):
- `sendMessage` (linha ~137): grava linha otimista `pending:true` via `_upsert`,
  chama `_setWorking(true, ...)`, seeda `_emitStreaming(StreamingMessage(
  inReplyTo: id))`, e manda `UserMessage`. Caminho offline (`ch == null`,
  linha ~159) faz return cedo com "held pending".
- Echo chega em `_onServerMessage`, case `UserInput(:id, ...)` (linha ~319):
  faz `_upsert(... copyWith(pending:false))` — é aqui que a mensagem confirma.
  Dedup é só por `id`.
- Já existe `_removeById(id)` (~linha 678) que apaga a mensagem do box. Use ele
  pra remoção silenciosa.

Implementação:
1. Adicione `final Map<String, Timer> _pendingSendTimers = {};` na classe.
2. Torne a duração injetável: parâmetro de construtor
   `Duration pendingSendTimeout = const Duration(seconds: 20)` (pra teste usar
   duração curta). Guarde em campo.
3. Em `sendMessage`, **somente no caminho em que o send é de fato tentado**
   (`ch != null`, depois do `ch.send`), inicie um `Timer(pendingSendTimeout,
   ...)` keyed por `id`. NÃO inicie no caminho offline (held pending é estado
   deliberado).
4. Quando o timer disparar:
   - `_removeById(id)` (remoção silenciosa).
   - Se `_streaming?.inReplyTo == id`, limpe o streaming seed
     (`_emitStreaming(null)`).
   - Se o "working"/spinner estava amarrado a esse `id`, limpe-o (veja o helper
     de clear em ~linha 130-135 e `_setWorking`). NÃO derrube working de OUTRA
     mensagem em andamento.
   - Remova o id de `_pendingSendTimers`.
   - `debugPrint('[msg-timeout] id=$id removed (no echo in '
     '${pendingSendTimeout.inSeconds}s)')`.
5. No case `UserInput` (echo): cancele e remova o timer desse `id`
   (`_pendingSendTimers.remove(id)?.cancel()`) junto do upsert — o echo chegou,
   não deve remover.
6. Cancele timers pra não vazar: no `dispose`/cleanup do serviço, e em qualquer
   reset de sessão/room (cancele todos e limpe o map). Procure onde o estado é
   resetado ao trocar de sessão/room e adicione o cleanup.
7. Também cancele o timer do `id` correspondente quando uma mensagem for
   cancelada pelo usuário, se aplicável (`cancel`).

Testes (`test/data/sync/sync_service_test.dart` ou o arquivo de teste
correspondente do sync_service — localize):
- (a) mensagem pending é removida após o timeout quando nenhum echo chega.
- (b) mensagem NÃO é removida quando o echo (`UserInput` com mesmo id) chega
  dentro da janela; timer é cancelado.
- (c) sem vazamento: timers cancelados no dispose/reset.
Use `pendingSendTimeout` curto + `fakeAsync` (package:fake_async) ou o padrão de
teste já usado no arquivo. NÃO use timer real de 20s.

NÃO mexa nos arquivos não relacionados com mudanças locais pendentes
(`speech_service.dart`, `input_bar.dart`, `speech_service_test.dart` — são de
voz, outra feature). Foque só no timeout de envio.

Verificação obrigatória antes de gravar resultado:
- `dart format .`
- `flutter analyze` (zero issues)
- `flutter test` (todos verdes)

No result file: resumo do diff + confirmação dos 3 comandos verdes. NÃO commitar.
