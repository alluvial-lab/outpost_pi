---
id: story-public-flip-shred-runbook
kind: story
stage: drafting
tags: [security, ops, release]
parent: feature-public-flip-branding-and-exposure
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-15
updated: 2026-08-15
---

# Public flip: targeted history shred + content redaction runbook

Operator direction 2026-08-15: `.work` STAYS (public work tracking is fine);
definitely shred specific IPs/PII from history; maybe shred upstream-referencing
history. NOT a wholesale .work purge.

## Sensitive-content inventory (history scans, 2026-08-15)

| Pattern | Commits touching | Current files |
|---|---|---|
| `<LAN-subnet>.*` (LAN) | 8 | AGENTS.md, scripts/herdr-setup.sh, .work/session-notes ×2, .work/backlog ×1 |
| `<tailnet-subnet>.*` (tailnet) | 4 | AGENTS.md, .work/session-notes ×3 |
| `dev-vm` (VM hostname) | 13 | AGENTS.md, .agents/skills ×3, .work ×5, fixtures ×2 |
| `kevoun.creates@proton.me` | every operator commit (~1,616) | commit metadata only |
| upstream contributors' emails | 231 pre-fork inherited commits | metadata only (already public in upstream repo) |

## Shred plan (ONE filter-repo pass, mirror-clone, verify before push)

1. **Path-drops (whole-file, all history):** the 3 incident session-notes
   (.work/session-notes/2026-07-26-tailscale*, 2026-07-27-releases*,
   2026-08-03-patchbay-keyring*) — narratives describe home-network topology
   and device ops; IP-replacement alone doesn't de-identify them. Everything
   else in .work stays.
2. **--replace-text rules (blob rewrite, all history):**
   - `<lan-host>` → `<lan-host>`; regex `192\.168\.50\.\d+` → `<lan-ip>`
   - `<tailnet-host>` → `<tailnet-host>`; regex `100\.106\.7\.\d+` → `<tailnet-ip>`
   - `dev-vm` → `dev-vm` (case variants)
   - `ssh agent@…` lines in scripts/herdr-setup.sh → generic
   - operator email → DECISION PENDING (see below)
3. **Optional truncation (DECISION):** drop the 231 pre-fork inherited
   upstream commits behind a single baseline commit ("Import from remote_pi
   at 02b2c92, MIT — see LICENSE/NOTICE") so public history = our 1,616-commit
   arc only. Our own pre-rebrand commits that mention remote_pi/remotepi stay
   (honest rebrand history, license-clean, low-value to redact).
4. **Pre-flip content edits (worktree, pre-rewrite commit):** public-facing
   AGENTS.md pass (deploy runbook → generic placeholders; keep workflow
   guidance), .agents/skills SKILL.md dev-vm mentions, herdr-setup.sh header.
5. **Mechanics:** mirror clone → filter-repo (all rules in one pass) →
   VERIFY (git log -S per pattern = 0 hits on mirror; tree builds; tags
   rewritten) → force-push → GitHub support ticket to purge cached
   old-SHA objects/views (data-exclusion request) → dependabot re-syncs.
   SHA note: pre-July-2026 + pre-fork SHAs survive only if the email rewrite
   is skipped; any blob/email rewrite rehashes affected commits + descendants.

## Open decisions (operator)

1. Operator commit email: keep `kevoun.creates@proton.me` (if intentionally
   public) or rewrite to `KevounC@users.noreply.github.com` (rewrites ~all our
   commit SHAs — free if truncation already chosen, costly alone)?
2. Truncate the 231 pre-fork upstream commits? (recommended: yes, single
   baseline import commit)
3. Session-notes: drop whole files as planned, or IP-redact and keep?
4. Public AGENTS.md: who does the editorial pass (agent draft + operator
   review is the usual)?
