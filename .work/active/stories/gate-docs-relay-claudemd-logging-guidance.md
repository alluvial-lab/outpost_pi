---
kind: story
release_binding: null
parent: feature-repair-current-state-docs
stage: done
id: gate-docs-relay-claudemd-logging-guidance
tags: [documentation]
depends_on: []
gate_origin: docs
created: 2026-07-01
updated: 2026-07-16
---

# relay/CLAUDE.md logging guidance references info_span! for handlers

## Severity
Low

## Location
relay/CLAUDE.md:30

## Issue
The doc still instructs using tracing::info_span! in handlers, but current relay handlers use info!/warn!/error! directly (with fields) without info_span! usage.

## Recommendation
Update the CLAUDE guidance to reflect actual relay logging practice (or clarify optional span usage) so handler logging conventions are current.
