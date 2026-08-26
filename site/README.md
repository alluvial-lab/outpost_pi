# Outpost-Pi — Site

Landing page for [Outpost-Pi](https://github.com/alluvial-lab/outpost_pi) — the
project that lets you control a Pi coding agent from your phone through a
self-hosted relay with Ed25519 challenge-response authentication. Direct relay
connections use cleartext `ws://`; `wss://` requires an external TLS-terminating
reverse proxy. After pairing, app↔Pi owner-channel payloads are end-to-end encrypted
and authenticated; the relay still sees routing metadata, and cross-PC Pi↔Pi envelopes
remain relay-readable.

This package provides these routes:

- `/` — landing (hero, features, quick start, GitHub CTA)
- `/cockpit` — Cockpit overview
- `/docs` — documentation
- `/download` — app and Cockpit downloads
- `/why` — product rationale
- `/tutorials` and topic pages — tutorials
- `/terms` — Terms of Service
- `/privacy` — Privacy Policy (LGPD)

Target domain: <https://outpost-pi.kevoun.com>.

## Stack

- Next.js 16 (App Router) + React 19
- TypeScript 5 (strict)
- Tailwind 4 (via `@tailwindcss/postcss`)
- ESLint 9
- Package manager: **pnpm**

Dual-mode theme (dark/light, following system preference by default); visual identity lives in `../branding/`.

## Commands

```bash
pnpm install   # install deps
pnpm dev       # dev server at http://localhost:3000
pnpm build     # production standalone build
pnpm start     # serve the production build
pnpm lint      # ESLint
```

## Layout

```
src/
├── app/
│   ├── layout.tsx              # Root layout: header + main + footer, global metadata
│   ├── page.tsx                # Landing
│   ├── cockpit/page.tsx        # Cockpit overview
│   ├── docs/page.tsx           # Documentation
│   ├── download/page.tsx       # App and Cockpit downloads
│   ├── why/page.tsx            # Product rationale
│   ├── tutorials/              # Tutorial index and topic pages
│   ├── terms/page.tsx
│   ├── privacy/page.tsx
│   ├── icon.svg                # Favicon (served as /icon.svg)
│   ├── opengraph-image.tsx     # Generated OG image (next/og)
│   └── globals.css             # Tailwind + design tokens
├── components/
│   ├── header.tsx              # Logo + nav
│   ├── footer.tsx              # Terms/Privacy/GitHub + copyright
│   ├── landing/                # Landing-specific components
│   ├── download/               # Download-specific components
│   ├── code-block.tsx          # Snippet block
│   └── legal-shell.tsx         # Shared shell for legal pages
└── lib/
    ├── app-release.ts          # Request-time app release manifest
    └── cockpit-release.ts      # Request-time Cockpit release manifest
```

## Conventions

- **Server components by default** — only opt into `"use client"` when state, events, or hooks are needed.
- **No backend / API routes** in the MVP. The site is purely presentational.
- **No analytics, no tracking cookies.** Aligned with the project's privacy posture.
- **English only** in the MVP. PT-BR is a separate plan if demand appears.

## Deploy

Production runs as a locally built standalone Docker image; use
`./build-docker.sh` to build it. Vercel is optional for contributor previews.
Domain wiring is handled outside this repo.
