# Session note — 2026-07-23 (late 2) — feature-diagnostic-privacy-hardening DONE

Transient handoff note. Delete when superseded.

## TL;DR

Designed and shipped `feature-diagnostic-privacy-hardening` in one session:
feature-design → implement-orchestrator (1 worker, 5 checkpoints) → standard
cross-model review (1 pass) → done. The 0.2.0 "content-free by construction"
diagnostic policy now covers the five residual leak surfaces (app
failure-diagnostics, cockpit RpcUnknown/LSP-stderr/formatter-reload/ck_trace)
PLUS two review-caught siblings (session-sync console line, held-resend
failure) PLUS the legacy-egress hole (pre-upgrade forbidden-key rows dropped
at ring load + export). Board state: implementing queue now holds only the 2
owner-identity-transition children (design-blocked) and
feature-reconnect-reproduction (children drafting).

## Key decisions / discoveries

- The "shared policy" the feature brief asked to design ALREADY existed (0.2.0
  `feature-redact-secrets-from-diagnostic-surfaces`); adopted verbatim.
- Brief's "one redactor module per subproject" rejected as over-abstraction;
  app's `debug_log.dart` IS the policy module and was tightened
  (`kAdmissibleFailureCodes`, `kForbiddenDiagnosticKeys`, constructor-level
  code admission). Cockpit keeps per-site fixed categories.
- Review pass-1 (Sol, REQUEST CHANGES): 2 blockers fixed (legacy JSONL egress,
  resend `$err`), 1 important fixed (constructor admission), 1 important
  parked (`idea-privacy-canaries-production-boundary-coverage`).

## Next pickups (priority)

1. `feature-design` on `feature-owner-identity-transition` (deps satisfied) —
   last design-blocked cluster before v0.3.0.
2. Design the 4 drafting children of `feature-reconnect-reproduction`.
3. `/release-deploy` v0.3.0 with everything bound.

Local main: 47 commits ahead of origin, nothing pushed.
