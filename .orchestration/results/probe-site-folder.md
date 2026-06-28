# [ORCH:probe-site-folder] Estrutura de pastas — site/

**Status**: done
**Arquivos tocados**: nenhum

## Resumo

Site NextJS em estado scaffold padrão (`create-next-app`). Apenas uma rota
(`src/app/page.tsx` + `layout.tsx`), assets SVG em `public/`, sem componentes
customizados ainda. Stack confirmada: Next 16 / React 19 / TS / Tailwind 4.

## Árvore (3 níveis, sem node_modules / .next / .git)

```
.npmrc
CLAUDE.md
eslint.config.mjs
next-env.d.ts
next.config.ts
package.json
pnpm-lock.yaml
pnpm-workspace.yaml
postcss.config.mjs
public/
  file.svg
  globe.svg
  next.svg
  vercel.svg
  window.svg
README.md
src/
  app/
    favicon.ico
    globals.css
    layout.tsx
    page.tsx
tsconfig.json
```

## Notas pro orquestrador

- Nenhuma página além da raiz existe ainda — tudo a criar.
- Sem pasta `src/components/`, `src/lib/`, ou similares.
