# Outpost-Pi — Site (NextJS)

Antes de editar ou revisar `site/`, leia a referência de stack em [`../.agents/skills/next-site/SKILL.md`](../.agents/skills/next-site/SKILL.md).

Landing page institucional do Outpost-Pi. Apresenta projeto, links pro GitHub,
documentação do MVP. **Apenas apresentação — não tem lógica de produto.**

## Stack

- NextJS 16 (App Router)
- React 19
- TypeScript 5
- Tailwind 4 (via `@tailwindcss/postcss`)
- ESLint 9
- Package manager: **pnpm** (com `allowBuilds` para `sharp` e `unrs-resolver` em `pnpm-workspace.yaml`)

## Comandos

- `pnpm install` — instala deps
- `pnpm dev` — dev server em :3000
- `pnpm build` — build de produção
- `pnpm start` — serve build
- `pnpm lint` — ESLint

## Convenções

- **Server Components por padrão** — só usar `"use client"` quando necessário (state, events, hooks)
- **Pasta de rotas**: `src/app/` (App Router)
- **Estilos**: Tailwind utility-first. Sem CSS modules / styled-components
- **Imagens**: `next/image` com fallback estático onde possível
- **Tipagem**: props de componentes sempre tipadas, sem `any`

## NÃO fazer

- Não adicionar features de produto (chat, pareamento, etc) — isso vai no `app/`
- Não comitar `.next/`, `out/`, `node_modules/` (já no .gitignore raiz)
- Não desabilitar lint pra fazer passar — corrigir o erro
- Não introduzir backend (API routes) sem registrar plano

## Publicação (deploy)

O site roda em produção (`outpost-pi.kevoun.com`) como **imagem Docker**,
construída localmente a partir de `site/` (sem publicação em registry). O host
de produção carrega a imagem local.

```bash
./build-docker.sh            # build local, tag :latest
./build-docker.sh v1.2.3     # tag :v1.2.3 E :latest
```

O que o script faz: builda para a plataforma do host a partir do
`Dockerfile` (multi-stage → `next build` com `output: "standalone"`, runtime
`node:22-alpine` na porta 3000 com healthcheck em `/`) e carrega a imagem
no daemon Docker local (sem `--push`).

Pré-requisitos: **`docker login`** (Docker Hub) feito antes, e `docker buildx`
(vem no Docker moderno). Sem login, o push falha no fim do build.

Fluxo típico de publicação: commit + push no git → `pnpm lint && pnpm build`
verdes → `./push-docker.sh` → o host redeploya da `:latest`. Passe uma versão
(`vX.Y.Z`) quando quiser uma tag fixada além da `:latest`.

## Modo orquestrado

Se receber um prompt começando com `[ORCH:<task-id>]`, leia
`../.orchestration/INSTRUCTIONS.md` antes de qualquer outra ação. Esse marker
indica que outro agente está coordenando o trabalho e tem regras específicas
(onde escrever resultado, não comitar, etc).
