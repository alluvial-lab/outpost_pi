# Outpost-Pi — Site (NextJS)

Before editing or reviewing `site/`, read the stack reference in [`../.agents/skills/next-site/SKILL.md`](../.agents/skills/next-site/SKILL.md).

Outpost-Pi's institutional landing page. Presents the project, GitHub links,
and MVP documentation. **Presentation only — it has no product logic.**

## Stack

- NextJS 16 (App Router)
- React 19
- TypeScript 5
- Tailwind 4 (via `@tailwindcss/postcss`)
- ESLint 9
- Package manager: **pnpm** (with `allowBuilds` for `sharp` and `unrs-resolver` in `pnpm-workspace.yaml`)

## Commands

- `pnpm install` — installs dependencies
- `pnpm dev` — dev server on :3000
- `pnpm build` — production build
- `pnpm start` — serves build
- `pnpm lint` — ESLint

## Conventions

- **Server Components by default** — use `"use client"` only when needed (state, events, hooks)
- **Routes directory**: `src/app/` (App Router)
- **Styles**: utility-first Tailwind. No CSS modules / styled-components
- **Images**: `next/image` with static fallback where possible
- **Typing**: component props always typed, no `any`

## Do NOT

- Do not add product features (chat, pairing, etc.) — that belongs in `app/`
- Do not commit `.next/`, `out/`, `node_modules/` (already in the root .gitignore)
- Do not disable lint to make it pass — fix the error
- Do not introduce a backend (API routes) without recording a plan

## Publishing (deploy)

The site runs in production (`outpost-pi.kevoun.com`) as a **Docker image**,
built locally from `site/` and loaded into the local Docker daemon (no registry
push). The production host runs the local image.

```bash
./build-docker.sh            # local build, :latest tag
./build-docker.sh v1.2.3     # :v1.2.3 AND :latest tags
```

What the script does: builds for the host platform from the
`Dockerfile` (multi-stage → `next build` with `output: "standalone"`,
`node:24-alpine` runtime on port 3000 with healthcheck at `/`) and loads the
image into the local Docker daemon (no `--push`, no registry login).

Prerequisites: `docker` with `buildx` (bundled with modern Docker). No Docker
Hub login or registry credentials are required — the image is project-local.

Typical publishing flow: commit + push to git → `pnpm lint && pnpm build`
green → `./build-docker.sh` → transfer the local image to the host and
redeploy from `:latest`. Pass a version (`vX.Y.Z`) when you want a pinned tag
in addition to `:latest`.

> **Note:** `site/README.md` mentions Vercel as an alternative deploy target
> for contributors who want zero-config Next.js hosting. The production
deployment uses the local Docker flow above; the two are not in conflict —
> Vercel is a contributor convenience, Docker is the production path.

## Orchestrated mode

If you receive a prompt starting with `[ORCH:<task-id>]`, read
`../.orchestration/INSTRUCTIONS.md` before any other action. This marker
indicates another agent is coordinating the work and has specific rules
(where to write results, do not commit, etc.).
