---
id: gate-security-mcp-tmp-config-path
kind: story
stage: implementing
tags: [security]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-10-04
updated: 2026-10-04
---

# Predictable MCP temporary file permits symlink following / config substitution

## Severity
Medium (ambient)

## Domain
Secrets & Configuration

## Location
`pi-extension/src/extension/command_surface/standalone_cli.ts:306-311`

## Evidence
`join(tmpdir(), \`outpost-pi-mesh-mcp-${process.pid}.json\`)` — predictable,
non-exclusive creation, follows existing symlinks, no private directory. On
shared temporary directories without protective OS restrictions another
local user can pre-position the path (overwrite victim-writable files or
substitute the execution-bearing MCP config before Claude reads it). Scanner
confirmed symlink-following via an isolated canary; cross-user exploitation
depends on filesystem protections.

## Remediation direction
Create an unpredictable owner-only temp directory (mkdtemp semantics),
exclusively create the config inside it, remove the directory on cleanup.
