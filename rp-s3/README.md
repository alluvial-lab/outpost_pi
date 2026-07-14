# rp-s3 — servidor de downloads do Outpost-Pi

Servidor HTTP mínimo (Rust + axum) que serve os instaladores do Cockpit (e
futuros produtos) a partir de um diretório montado como volume. Roda em
container na VPS atrás do proxy que termina TLS em
`https://rp-s3.jacobmoura.work`.

É o lado "leitura" do passo 4 do [plano 43](../plan/43-cockpit-packaging.md).
A VPS não tem acesso SSH, então o fluxo é: o CI (`cockpit-release.yml`)
publica os binários como assets da **GitHub Release** `cockpit-v<versão>` e
anexa o `latest.json` (com as URLs desses assets); o usuário coloca o
`latest.json` manualmente no volume deste host — é o gate de publicação. O
rp-s3 serve o manifest na URL estável que o site consome.

## Rotas

| Rota | Comportamento |
|---|---|
| `GET /healthz` | `200 ok` |
| `GET /downloads/<produto>/...` | arquivos de `DATA_DIR/<produto>/...` |

Regras de resposta em `/downloads`:

- `.dmg`/`.exe`/`.deb`/`.rpm`/`.zip` → `Content-Disposition: attachment` +
  `Cache-Control: immutable, 1 ano` (artefatos vivem em pastas versionadas,
  a URL nunca é reusada).
- Demais arquivos (`latest.json`, `SHA256SUMS`) → `Cache-Control: max-age=300`
  (URL fixa, release novo propaga em ≤5 min).
- `Access-Control-Allow-Origin: *` em tudo (o site lê o manifest de outro
  domínio).
- Sem listagem de diretório; diretório sem index → 404.

## Configuração

| Env | Default | Descrição |
|---|---|---|
| `DATA_DIR` | `/data` | raiz servida em `/downloads` |
| `PORT` | `8080` | porta HTTP (TLS fica no proxy) |
| `RUST_LOG` | `rp_s3=info,tower_http=info` | nível de log |

## Layout do volume

O `docker-compose.yml` monta o deploy path do CI **como o subdiretório do
produto** — assim o host fica plano e a URL ganha o prefixo certo:

```
host:  /Users/flutterando/cockpit/data/          (colocado manualmente)
         latest.json
         SHA256SUMS                              (opcional)

mount: /Users/flutterando/cockpit/data → /data/cockpit (read-only)

URL:   https://rp-s3.jacobmoura.work/downloads/cockpit/latest.json
```

Os binários em si vivem nos assets da GitHub Release — as URLs dentro do
`latest.json` apontam pra lá. O servidor continua sabendo servir
`.dmg`/`.exe`/`.deb`/`.rpm` como attachment caso um dia algum arquivo seja
hospedado aqui também.

Produto novo no futuro = outro volume montado em `/data/<produto>`.

## Rodar

```bash
# local, sem docker
DATA_DIR=./exemplo PORT=8080 cargo run

# na VPS (carrega a imagem local)
docker compose up -d
curl -fsS http://localhost:8080/healthz
```

## Buildar a imagem Docker

Mesmo fluxo do relay: o script lê a versão do `Cargo.toml`, builda para a
plataforma do host e carrega a imagem local como `outpost-pi-rp-s3:v<versão>`
+ `:latest` (sem `--push` — imagem project-local).

```bash
./build-docker.sh
```

O proxy reverso da VPS aponta `rp-s3.jacobmoura.work` → `localhost:8080`.
