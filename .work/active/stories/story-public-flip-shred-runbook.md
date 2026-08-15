---
id: story-public-flip-shred-runbook
kind: story
stage: done
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

## EXECUTED 2026-08-15 — see .work/session-notes/2026-08-15-shred-execution.md (local)

Result: origin force-pushed; main = 1,606 commits rooted at the import
commit; all patterns zero history-wide; pre-fork truncated; session-notes
dropped; cockpit-v1.5.1 (upstream tag) removed; fix/stale-context-reconnect
deleted on origin, preserved as local/fix-stale-context-reconnect.
GitHub cache-purge ticket drafted in the session note — operator files it.
Flip: DONE 2026-08-15 (repo public). Cache-purge ticket: operator waived it
2026-08-15 — accepted risk: old-SHA objects unreachable except by exact hash;
sensitive values are internal-only (LAN/tailnet IPs, hostname) behind the
operator's firewall; GitHub caches age out on their own. Story complete.

## Operator decisions (recorded 2026-08-15)

1. Commit email `kevoun.creates@proton.me`: **KEEP** (intentional public identity).
2. Truncate pre-fork upstream commits: **YES** — graft recipe: after the
   path/replace pass, `newroot=$(git commit-tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904 -m "Import from remote_pi at 02b2c92 (MIT) — see LICENSE/NOTICE")`,
   `git replace --graft <first-post-fork-commit> $newroot`, re-run
   filter-repo to bake. Public history = our ~1,616-commit arc only.
3. Session-notes: **gitignored going forward + path-dropped whole** from
   history (landed in worktree: .work/session-notes/ ignored, 3 tracked
   files untracked-but-kept-on-disk; filter-repo gains --path
   .work/session-notes). NOTE: other session notes exist on disk untracked;
   history path-drop removes the whole dir from all history.
4. Public AGENTS.md: **drafted, operator review pending** — sanitized edition
   in worktree; full runbook preserved in gitignored AGENTS.local.md.

Residual accepted after scrub (operator may veto at flip review): AGENTS.md
historical versions keep runbook prose minus IP/hostname strings
(replace-text covers <LAN-subnet>.*, <tailnet-subnet>.*, dev-vm, the mock relay URL).
