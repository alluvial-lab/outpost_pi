# Handoff to skills/ session — `REMOTE_PI_DEBUG_LOG` use-case gap in `feature-pi-sandbox-env-add-config`

**To:** the `skills/` repo session implementing `feature-pi-sandbox-env-add-config`.
**From:** Remote Pi fork session, 2026-07-09 (commit 37f1462).
**Purpose:** describe exactly what Remote Pi needs from env-var passthrough, and why `envAdd` as currently scoped does not cover it — so the design pass can decide whether to extend scope or document the limitation.

---

## The precise need

The remote_pi pi-extension has a delivery-path debug log (bounded ring + file at
`~/.pi/remote/debug/delivery.log`) gated behind `REMOTE_PI_DEBUG_LOG=1`. It is
read at **module-load time**, not at a hook:

- `pi-extension/src/session/delivery_debug_log.ts:250` —
  `createDeliveryDebugLog()` does `if (process.env["REMOTE_PI_DEBUG_LOG"] !== "1")
  return noopDeliveryDebugLog;`.
- `pi-extension/src/index.ts:1219` — `let _deliveryDebugLog =
  createDeliveryDebugLog();` is **top-level module code**, not inside
  `session_start`. It runs when the extension module is first imported by pi's
  extension loader — before any `session_start` hook fires.

So the var must be present in `process.env` **before the remote_pi extension
module loads**. Setting it later (e.g. in a `session_start` hook) is too late:
the log instance is already the no-op.

## Why `envAdd` as scoped does not reach it

`envAdd`'s touch surface threads the config into `createSandboxedBashOps`'s
`buildMinimalEnv` call — i.e. the env of **bash-tool subprocesses** spawned by
the sandboxed bash operations. That governs the env of commands run via the
`bash` tool. It does **not** govern the env of pi's own process.

The pi-sandbox extension loads **inside** pi and mediates tools; it does not
wrap or re-exec pi's own session (`sandbox.ts:2-19` — "OS-level sandboxing for
mediated bash + file tools"; `session_start` at `:498` "intentionally leaves
process.env untouched"). pi's own process env is fixed by whatever launched pi —
in the Remote Pi dev environment, an **outer bwrap at PID 1** (constructed by
the code-server/dev-VM launch layer, `--clearenv` + a hardcoded `--setenv`
allowlist of `PATH/HOME/TERM/LANG`) that strips `REMOTE_PI_DEBUG_LOG` before pi
starts. The pi-sandbox extension cannot influence that layer — it has not
loaded yet when the outer bwrap runs.

Consequence: even with `envAdd` implemented, setting `"envAdd": {"values":
{"REMOTE_PI_DEBUG_LOG": "1"}}` in `~/.pi/agent/extensions/sandbox.json` would
inject the var into **bash-tool subprocesses** but NOT into pi's own
`process.env`, so the delivery log would stay a no-op.

## What would actually solve it (three options, for design to weigh)

1. **Outer-launch config (outside the skills repo).** Add `--setenv
   REMOTE_PI_DEBUG_LOG 1` to the PID 1 bwrap / code-server launch. Robust
   unblock, but lives in dev-VM provisioning, not the skills repo or the
   pi-sandbox extension. `envAdd` cannot help here.

2. **Apply `envAdd.values` to `process.env` at the sandbox extension's own
   module load (in-repo, order-fragile).** The sandbox extension loads before
   the remote_pi extension in the current `settings.json` `packages` order
   (sandbox via the skills git package at index 1; remote_pi at index 4), so
   the sandbox extension's top-level module code runs before remote_pi's
   `index.ts:1219`. If the sandbox extension read `envAdd.values` at its own
   module load and did `process.env[k] = v` for each, the var would be present
   when remote_pi loads. **Caveats:**
   - (a) this depends on extension load order — the *locally-tested* sandbox
     path (`../../projects/skills/plugins/pi-sandbox`, index 5) loads **after**
     remote_pi (index 4), so under that registration the hack silently fails;
   - (b) pi does not guarantee sequential array-order extension loading across
     versions;
   - (c) injecting into the host pi process's `process.env` is a bigger trust
     grant than injecting into bash subprocesses and needs its own security
     framing (the strategic-decision "global/operator-only" rationale applies
     even more strongly here);
   - (d) `passthrough` cannot help for this var (the outer bwrap already
     stripped it from the host env — there's nothing to copy), so only
     `values` (literal injection) works.

3. **A pi-core `env` block in `settings.json`** applied to `process.env`
   before extensions load. Robust in-process solution but lives in
   `@earendil-works/pi-coding-agent` (pi core), not the skills repo.

## Recommendation for the design pass

- **Do not silently expand `envAdd`'s scope to "also mutate pi's own
  `process.env`"** — that is a distinct trust surface from subprocess env and
  deserves its own explicit config field and security rationale (option 2).
- **Either** (a) extend this feature with an explicit, separately-named field
  (e.g. `envInject` / `hostEnv`) that applies `values` to `process.env` at
  module load, documented as order-dependent and operator-only, **or** (b)
  keep this feature subprocess-only and record that the `REMOTE_PI_DEBUG_LOG`
  use case is out of scope for the pi-sandbox extension and must be solved at
  the outer-launch layer (option 1) or in pi core (option 3).
- If (b), the Remote Pi fork will unblock itself via the outer-bwrap config
  regardless; this feature remains correct and valuable for its subprocess
  scope.

## Provenance

Full analysis: `remote_pi/.work/session-note-2026-07-09-outbound-delivery-gap-scope-and-debug-env.md`
(commit 37f1462). Downstream consumer: `/home/agent/projects/remote_pi/pi-extension`
(delivery debug log at `src/session/delivery_debug_log.ts`).
