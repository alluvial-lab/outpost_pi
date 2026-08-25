---
id: epic-rebrand-to-outpost-pi-en-first-site
kind: feature
stage: done
tags: [rebrand, docs, i18n, site]
parent: epic-rebrand-to-outpost-pi-en-first
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-14
updated: 2026-07-15
---

# EN-first + JSDoc gap-fill — site

## Brief

Translate Portuguese → English and adopt the JSDoc documentation framework in
`site/` (Next/React). 2 PT-bearing files: `site/src/app/icon.svg` (SVG comment
prose) and `site/src/app/tutorials/daemon/page.tsx` (a tutorial page — likely
PT body copy). The tutorial page is the design-bearing surface: its PT is
user-facing prose, not code comments, so it needs translation-review, not
mechanical sed.

Covers `site/src/` only. Gap-fill scope is the Always tier per the doc
convention: exported React component functions and hooks get JSDoc `/** */`
comments. React components don't have a single canonical doc framework; the
convention uses JSDoc on exported component functions/hooks where idiomatic.

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi-en-first`
- Position in epic: independent tiny slice. No `depends_on` — the site's
  product-identity strings already migrated in the first rebrand epic. Can
  run in parallel with every other child feature.

## Foundation references
- `.agents/skills/documentation-conventions/SKILL.md` — JSDoc-on-components
  format and the Always tier for React (exported components/hooks).
- `.agents/skills/next-site/SKILL.md` — site code reference; read before
  editing `site/`.
- Parent epic `## Grounded surface measurement` — the 2-file count.

## What this feature does NOT cover
- Product-identity string renames — owned by the mechanical-rename feature.
- Generated/vendored state (`.next/`, `node_modules/`).
- The `icon.svg` PT is SVG comment prose (`<!-- ... -->`) — translate to EN;
  no gap-fill (SVG is Skip tier).

## Verification
```bash
# from site/
pnpm lint && pnpm build
```
Plus a grep confirming zero PT (accented Latin) in `site/src/`.

## Design decisions
- **Translation method**: Translate the eight SVG comments mechanically, but review the daemon tutorial snippet in context — comments are safe literal prose, while the tutorial snippet is a user-visible instruction and must preserve its command and timezone semantics.
- **Daemon-page accented hit**: Change the explanatory snippet comment to idiomatic ASCII English (`# every weekday at 9am, Sao Paulo time`) while retaining the exact `America/Sao_Paulo` IANA identifier and all CLI tokens. The measured `São` is a place name rather than a Portuguese sentence, but ASCII source is required by this slice's zero-accented-Latin verification; `Sao Paulo` is the identifier's conventional ASCII spelling.
- **React documentation boundary**: Audit all exported JSX-returning component functions in `site/src/**/*.tsx` and document each currently undocumented export with an EN JSDoc summary. Do not extend this slice to route metadata, `site/src/lib/` release-manifest helpers, private helpers, type declarations, CSS, tests, or SVGs; those are not exported React component/hook targets.
- **Component audit result**: The initial inventory contains 61 exported React component functions, 9 already carrying suitable EN JSDoc comments, 52 gaps, and no exported hooks. Retain the nine existing comments unless an implementation-time accuracy review finds one stale.
- **Work shape**: Keep this as one implementation unit without child stories. The two translation files and the documentation inventory share one small, presentation-only verification gate; splitting mechanical comments from JSDoc would add queue overhead without independent behavior or a useful dependency boundary.
- **Dispatch rationale**: Direct-read mapping covered the two translation files, all React exports, existing JSDoc examples, and the site verification contract. No exploratory fan-out was needed because the entire bounded surface is known and has no architectural uncertainty.

## Architectural choice

### Option A — Change only the two measured PT-bearing files
Translate the SVG comments and the daemon-page hit, then stop. This minimizes
churn, but leaves the explicit JSDoc gap-fill commitment unfulfilled.

### Option B — Mechanical bulk JSDoc generation
Generate a one-line comment for every `export function` from a pattern. This
is fast but likely produces tautological docs, incorrectly treats non-component
exports as targets, and cannot distinguish user-facing components from tiny
icon primitives.

### Option C — Bounded, reviewed source audit (chosen)
Use the verified component inventory as a checklist, write concise EN JSDoc
that describes each component's rendering role or interactive contract, and
manually preserve all routes, props, and server/client boundaries. This keeps
the static site presentation-only, satisfies the component-level convention,
and avoids behavioral edits. It is chosen over A because the parent epic
requires gap-fill, and over B because documentation must record intent rather
than restate a generated name.

## Implementation Units

### Unit 1: Translate the two measured Portuguese-bearing sources

**Files**:
- `site/src/app/icon.svg`
- `site/src/app/tutorials/daemon/page.tsx`

**Planned edits**:

```svg
<!-- Solid black background -->
<!-- Pi symbol (geometric; font-independent) -->
<!-- Centered in the canvas, inside Android's safe zone (~66% of the canvas) -->
<!-- Upper horizontal bar -->
<!-- Left leg -->
<!-- Right leg -->
<!-- Subtle curve at the right foot (extension to the right) -->
<!-- Distinctive blue dot, positioned in the upper-right corner -->
```

```tsx
<CodeBlock
  code={`# every weekday at 9am, Sao Paulo time
outpost-pi cron add 4e39152d "0 9 * * 1-5" "Summarize the new PRs" --tz America/Sao_Paulo`}
  label="Schedule a prompt"
  language="bash"
/>
```

**Implementation notes**:
- Change prose only. Do not alter SVG geometry, colors, XML metadata, JSX,
  CLI names, cron syntax, daemon identifiers, or the IANA timezone identifier.
- Review the tutorial as rendered documentation: the surrounding copy is
  already EN, so the sole measured hit is the explanatory code comment, not
  a Portuguese body paragraph.

**Acceptance criteria**:
- [ ] `icon.svg` contains only EN SVG comment prose and its rendered icon is
  byte-for-byte equivalent apart from comments.
- [ ] The daemon snippet explains the timezone in English without changing the
  `outpost-pi cron add` invocation or `America/Sao_Paulo` value.
- [ ] No accented-Latin match remains in `site/src/` source after the scoped
  vocabulary review.

### Unit 2: Fill JSDoc gaps for exported React components

**Files and audit checklist**:

- Route components (16 gaps):
  - `site/src/app/cockpit/page.tsx` — `CockpitPage`
  - `site/src/app/docs/page.tsx` — `DocsPage`
  - `site/src/app/download/page.tsx` — `DownloadPage`
  - `site/src/app/layout.tsx` — `RootLayout`
  - `site/src/app/opengraph-image.tsx` — `OpengraphImage`
  - `site/src/app/page.tsx` — `Home`
  - `site/src/app/privacy/page.tsx` — `PrivacyPage`
  - `site/src/app/terms/page.tsx` — `TermsPage`
  - `site/src/app/tutorials/claude-mesh/page.tsx` — `ClaudeMeshTutorial`
  - `site/src/app/tutorials/cockpit-team/page.tsx` — `CockpitTeamTutorial`
  - `site/src/app/tutorials/daemon/page.tsx` — `DaemonTutorial`
  - `site/src/app/tutorials/getting-started/page.tsx` — `GettingStartedTutorial`
  - `site/src/app/tutorials/mesh-local/page.tsx` — `MeshLocalTutorial`
  - `site/src/app/tutorials/mesh-remote/page.tsx` — `MeshRemoteTutorial`
  - `site/src/app/tutorials/page.tsx` — `TutorialsIndexPage`
  - `site/src/app/why/page.tsx` — `WhyPage`
- Shared-components gaps (7):
  - `site/src/components/docs-shell.tsx` — `DocsSubsection`, `InlineCode`, `DocsTable`
  - `site/src/components/footer.tsx` — `SiteFooter`
  - `site/src/components/header.tsx` — `SiteHeader`
  - `site/src/components/landing/hero.tsx` — `Hero`
  - `site/src/components/landing/install.tsx` — `Install`
- Landing icon gaps (23):
  - `site/src/components/landing/icons.tsx` — `LogoMark`, `IconGateway`, `IconAlwaysOn`, `IconMesh`, `IconMic`, `IconImage`, `IconOpenSource`, `IconSelfHost`, `IconArrow`, `IconCopy`, `IconCheck`, `IconStar`, `IconGithub`, `IconApple`, `IconWindows`, `IconLinux`, `IconAndroid`, `IconPlay`, `IconDownload`, `IconChevronLeft`, `IconTerminal`, `IconPaperclip`, `IconStop`
- Landing and legal composition gaps (6):
  - `site/src/components/landing/sections.tsx` — `Pillars`, `GetApp`, `Strip`, `GithubCTA`
  - `site/src/components/legal-shell.tsx` — `LegalShell`, `LegalSection`

**Existing EN JSDoc to retain and validate** (9 components):
`Callout`, `CodeBlock`, `DocsSection`, `DocsToc`, `ShaCopy`, `InstallTabs`,
`RevealController`, `Pager`, and `Tabs`.

**Component signature and comment form**:

```tsx
/** Render the daemon-mode tutorial and its operational examples. */
export default function DaemonTutorial() {
  // Existing JSX unchanged.
}

/** Render a reusable documentation subsection heading and content. */
export function DocsSubsection({
  id,
  title,
  children,
}: {
  id?: string;
  title: string;
  children: ReactNode;
}) {
  // Existing JSX unchanged.
}
```

**Implementation notes**:
- Write `/** */` immediately before each exported component function. The
  summary must state rendering purpose, user interaction, or server/client
  responsibility where that context is non-obvious; do not restate inferred
  prop types or document JSX implementation details.
- Preserve exact component signatures, existing Server Component defaults, and
  existing narrow client boundaries (`"use client"`). Documentation must not
  introduce hooks, event behavior, props, metadata changes, or visual changes.
- Do not use a brittle generated comment template as acceptance evidence;
  manually review the checked inventory and retain the nine valid EN comments.

**Acceptance criteria**:
- [ ] Each of the 52 listed component gaps has a concise EN JSDoc comment
  directly preceding its export.
- [ ] The 9 existing component JSDoc comments remain EN and accurate.
- [ ] No exported hook exists in `site/src/`; therefore none requires a new
  hook doc comment.
- [ ] No `site/src/lib/` export, metadata constant, private helper, type-only
  declaration, test, CSS file, or SVG receives out-of-scope gap-fill.

## Implementation Order

1. Re-run the export and existing-JSDoc inventory against `site/src/` to guard
   against concurrent changes, then apply the reviewed EN translations in the
   two measured files.
2. Add and review component-level JSDoc for the 52 audited gaps, organized by
   route components, shared components, landing icons, and composition/legal
   components; validate the 9 existing comments at the same time.
3. Run the source-language and component-inventory checks, then from `site/`
   run `pnpm lint && pnpm build`.

## Testing

### Source and documentation audit

No behavior-specific unit test is appropriate: this feature changes only
comments and static tutorial copy. Verification instead proves the source
contracts directly:

```bash
# From repository root: no accented Portuguese-bearing source text remains.
rg -nP '[À-ÖØ-öø-ÿ]' site/src --glob '*.{ts,tsx,svg}'

# From repository root: enumerate the React component audit surface for manual
# comparison with the checklist above.
rg -n 'export (default )?(async )?function ' site/src --glob '*.tsx'

# From site/: validate TypeScript, lint rules, App Router compilation, and the
# standalone production build.
pnpm lint && pnpm build
```

The accented-Latin command is expected to produce no output. The export query
is an inventory aid rather than a substitute for reviewing whether a JSDoc
comment immediately precedes each target; inspect every listed gap and each
existing comment as part of the implementation review.

### Integration coverage

`pnpm build` renders and type-checks the changed App Router page while preserving
its existing Server/Client component boundaries. It is the integration proof
that the tutorial page, all imported shared components, and the static asset
still compile together.

## Risks

- **Accent scan false positives**: names and identifiers can legitimately use
  non-ASCII text. Mitigation: review each current hit, use ASCII `Sao Paulo`
  only in explanatory prose, and preserve `America/Sao_Paulo` exactly.
- **Documentation churn becoming behavior churn**: adding comments near
  `"use client"`, metadata, or dense JSX could accidentally change code.
  Mitigation: make comment-only diffs outside Unit 1, keep component bodies and
  imports untouched, and rely on lint plus production build.
- **Audit drift**: a concurrent export could make the 61/9/52 count stale.
  Mitigation: repeat the export inventory immediately before implementation and
  update this item if the source surface changes rather than silently omitting
  a target.

## Mockups

Not applicable. This changes existing static tutorial prose and source comments
only; it introduces no screen, flow, visual composition, or interaction. The
parent epic has no relevant mockup coverage, and fallback mockups are correctly
skipped.

## Other agent review

- Not invoked: this is a bounded, presentation-only documentation and copy
  slice with no architectural choice, protocol boundary, or irreversible
  decision. The design uses direct source inspection instead of advisory
  fan-out; the implementation review/build gate remains required.

## Child stories

None. The work is a single cohesive implementation stride with one shared
source audit and one site build gate.

## Implementation notes
- Files changed: `site/src/app/icon.svg`; 16 App Router component files under `site/src/app/`; `site/src/components/docs-shell.tsx`, `footer.tsx`, `header.tsx`, `legal-shell.tsx`, and `landing/{hero,icons,install,sections}.tsx`.
- Tests added: none; this documentation and comment-only slice uses the specified source audit, lint, and production build checks.
- Discrepancies from design: the brief's provisional suggestion that the daemon tutorial likely had Portuguese body copy was not borne out by the current source; only the specified explanatory code comment contained accented text, so the bounded Unit 1 edit was applied.
- Adjacent issues parked: none.
- Verification rationale: the environment had no `pnpm` on `PATH`; used Corepack with a writable temporary store and the locked dependencies, then ran the specified lint and production build successfully.
`
## Review (2026-07-15, standard, cross-model fresh-context)

Reviewer: `openai-codex/gpt-5.6-sol` (different model class from the umans
orchestrator). One balanced pass over the integrated feature diff
(`376fa38..HEAD -- site/`).

### Findings (adjudicated)
- **Important — tautological JSDoc on icon primitives** (`site/src/components/landing/icons.tsx`): 23 single-line `/** Render the X icon. */` comments sat above zero-prop, equivalently named icon components — obvious-description padding, not intent docs. Per the documentation-conventions Skip tier, removed. **Fixed.**
- No other findings; translation complete, no behavior/contract/identifier drift.

### Verification of fixes
- `corepack pnpm lint` (eslint) clean.
- `corepack pnpm build` succeeds; all routes prerendered.

### Verdict
Approve. Advanced `review → done`.
