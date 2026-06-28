Bug em produção: envio de imagem do app fica "sending…" pra sempre. Causa-raiz
confirmada: o relay derruba o envelope da imagem em silêncio por causa do teto
`MAX_CT_BYTES`.

Contexto técnico (já investigado, não precisa reconfirmar):
- `src/protocol/outer.rs:21` → `pub const MAX_CT_BYTES: usize = 1024 * 1024;` (1 MiB)
- `parse_line` (mesmo arquivo, ~linha 34-41) estima `env.ct.len() * 3 / 4` e
  retorna `ParseError::TooLarge` se passar do teto.
- A imagem passa por base64 duplo (inner `MessageImage.data` + outer `ct`),
  então a estimativa do relay ≈ 1,333 × o JPEG bruto. O app comprime até 1,5 MB
  (teto), o que vira ~2 MB na estimativa. Com teto de 1 MiB, qualquer imagem
  > ~768 KB é dropada.
- O handler só loga `"invalid envelope, dropping"` e não devolve nada — por isso
  o app nunca recebe echo e a mensagem trava "sending…".

Tarefa: tornar o limite **configurável por env, com default 4 MiB**.

1. Trocar a const fixa por um valor lido de env var na inicialização. Nome
   sugerido: `RELAY_MAX_CT_MIB` (inteiro, em MiB; default 4). Converta pra bytes
   internamente. Ausência/valor inválido cai no default — SEM panic (convenção
   do relay: zero unwrap/expect em prod). Use `OnceLock` (ou equivalente
   idiomático) pra ler uma vez.
2. `parse_line` deve usar o valor configurado em vez da const fixa.
3. Logue o valor efetivo no startup via `tracing` (info), ex:
   `info!(max_ct_bytes = N, "outer envelope size limit")`. Nunca `println!`.
4. Ajuste os testes em `src/protocol/outer.rs`:
   - `rejects_too_large` hoje usa string de 2 MiB (estimativa 1,5 MiB) — com
     default 4 MiB isso PASSARIA agora. Atualize pra exceder 4 MiB (ex.: 12 MiB
     de "A" → estimativa 9 MiB).
   - Adicione teste cobrindo que um payload de ~2 MB (estimativa) PASSA com o
     default 4 MiB (regressão do bug da imagem).
   - Se viável, cubra o override do limite. Cuidado com testes paralelos lendo
     env global — prefira injetar o limite como parâmetro testável (ex.:
     `parse_line_with_max(line, max)`) e manter a API pública limpa. Fica a teu
     critério arquitetural.
5. Não suba/baixe outros limites (o cap HTTP de mesh em `mesh/handler.rs` é
   separado e fora de escopo).

Verificação obrigatória antes de gravar resultado:
- `cargo fmt`
- `cargo clippy -- -D warnings` (deve passar limpo)
- `cargo test` (todos verdes)

No result file reporte: nome final da env var + formato, valor default em bytes,
e o resumo do diff (arquivos/linhas). NÃO commitar.
