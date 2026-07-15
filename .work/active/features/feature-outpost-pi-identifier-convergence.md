---
id: feature-outpost-pi-identifier-convergence
kind: feature
stage: drafting
tags: [rebrand, protocol, pi-extension, app, relay, docs, testing]
parent: epic-rebrand-to-outpost-pi
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Finish active Outpost-Pi identifier convergence

## Brief

Complete the active product-identity conversion missed by the core rebrand review. Outpost-Pi still carries pre-rebrand names in the canonical protocol package and schema, generated-contract descriptions, active fixtures, and extension test/runtime aliases. These are maintained product identifiers rather than provenance and should converge on `Outpost-Pi`, `outpost-pi`, or `outpost_pi` as appropriate.

This feature absorbs the backlog findings `gate-cruft-legacy-protocol-identifiers` and `rebrand-cross-client-auth-contract-test`. The latter belongs here because the auth-domain name is duplicated across Dart, TypeScript, and Rust; a shared vector or generated contract must protect the hard-cutover identifier from future half-renames.

## Scope boundary

Design and implementation should inventory active occurrences before editing and distinguish product identity from intentional legacy evidence. Expected surfaces include:

- `protocol/package.json`, the umbrella schema filename and references, schema titles/descriptions, `protocol/schema/manifest.json`, and `protocol/README.md`;
- active protocol fixtures and protocol-codegen tests that display or describe the old product name;
- active `remotePi*` extension aliases and test-harness names that no longer describe a compatibility boundary;
- current agent/operator documentation that still names the live product or workspace “Remote Pi”;
- the cross-language `outpost-pi-relay-auth-v1\n` contract and tests;
- the live `remote-pi-data` relay volume name, which requires an explicit state-preserving migration decision rather than a blind rename or silent abandonment.

Preserve unchanged:

- `LICENSE`, `NOTICE`, README acknowledgements, and factual provenance;
- historical `.work/`, release, research, and changelog records;
- legacy-rejection tests and pre-rebrand cleanup commands whose old literal is the behavior under test;
- genuine third-party dependency coordinates;
- wire/install compatibility literals that are intentionally retained and documented;
- absolute `/home/agent/projects/remote_pi` checkout paths until the separate cwd migration.

## Design handoff

The design pass should derive a concrete keep/change allowlist, choose the canonical schema/package names, decide how the auth-domain contract is shared across languages, and define a non-destructive relay-volume migration or an explicit compatibility retention rule. No global search-and-replace is acceptable.
