# Outpost-Pi — Orchestrator

You are at the **root** of the Outpost-Pi monorepo. This folder is exclusively for **planning**.

Before planning, implementing, or reviewing, also read `AGENTS.md` and the agent-neutral rules in `.agents/rules/`. They are the canonical surface shared by Claude, Pi, Codex, and other agents; this file retains the Claude/cmux persona and orchestration.

## What to do here

- Read and write `plan/NN-<slug>.md` (e.g. `plan/03-protocol.md`)
- Discuss architecture, product decisions, trade-offs
- Refine existing plans based on feedback
- Indicate which subproject receives the next implementation

## What NOT to do here

- Do not edit code in `app/`, `pi-extension/`, `relay/`, `site/`, `cockpit/`
- Do not run subproject build/test commands from here
- To implement something, dispatch through `cmux send` to the target subproject
  pane (see [Panes in this cmux workspace](#panes-in-this-cmux-workspace)
  below). Only ask the user to open a new terminal if the pane is gone.

## Structure

See [README.md](./README.md) for an overview and [plan/](./plan/) for the plans.

## Decisions already made

Before proposing a change of direction (architecture, pairing, scope, UI, security),
read [`plan/00-decisions.md`](./plan/00-decisions.md). That file lists decisions
settled in exploratory discussion and **must not be revisited without strong evidence**.

If you still want to revisit one, open an explicit discussion — do not change it silently.

## Plan conventions

- Sequential numbering: `01-bootstrap.md`, `02-ai-orchestration.md`, ...
- Each plan has: Context, Expected structure, Steps with acceptance criteria, DoD, Next plans
- Plans describe **what** + **how to verify**, not the complete code
- Pseudocode or exact commands are welcome; real implementation stays in the subproject

## When to promote a plan to implementation

When the plan has user acceptance and the steps are concrete enough for an agent to
execute, open Claude in the target subproject and provide the plan as context. The
agent for that subproject will follow its own persona.

## Available scouts

To snapshot the state of any subproject before planning, invoke the Scout subagents
in parallel through `Task` — they are read-only and report in a fixed format:

- `scout-app` — Flutter (`app/`)
- `scout-pi-extension` — Node/TS (`pi-extension/`)
- `scout-relay` — Rust (`relay/`)
- `scout-site` — NextJS (`site/`)
- `scout-cockpit` — Flutter Desktop (`cockpit/`)

Dispatch multiple in one message to run them in parallel. Each report returns Stack &
versions, Dependencies, Structure, Health (lint/build/tests), and detected Smells.

## Panes in this cmux workspace

This workspace ("Outpost-Pi") has 5 dedicated panes — one per subproject — plus this
Orchestrator. Each pane already has a `claude` running in its own session. **Use the
existing panes instead of asking the user to open a new terminal.**

| Pane (title) | Subproject (cwd) |
|---|---|
| `App` | `app/` |
| `Relay` | `relay/` |
| `Extension` | `pi-extension/` |
| `Site` | `site/` |
| `Cockpit` | `cockpit/` |
| `Orchestrator` (you) | monorepo root |

> **Cockpit is the newest pane** and is currently **started manually** by the
> user — it is **not yet** in `cmux-bootstrap-agents.sh` (which creates the 4
> originals: App/Relay/Extension/Site). When orchestrating, dispatch to `Cockpit`
> normally when the pane exists; if it is missing, ask the user to start it (do not
> assume that the bootstrap script creates it).

> **Never hardcode surface IDs in this documentation.** They change with every
> pane bootstrap. Always resolve by title through `cmux tree`.

### Discover the surface ID by title

```bash
# helper: prints the surface:N of the pane with title <Name>
surface_of() {
  cmux tree | awk -v t="$1" '
    $0 ~ "\""t"\"" {
      for (i = 1; i <= NF; i++) if ($i ~ /^surface:/) { print $i; exit }
    }
  '
}

surface_of Extension   # prints the current surface:N
```

### Dispatch a task to a pane (orchestrated mode)

**Always** use the `scripts/cmux-dispatch.sh` wrapper. It resolves the surface by
title, injects `[ORCH:<task-id>]`, and sends + Enter in one call:

```bash
scripts/cmux-dispatch.sh Extension 03-ts-codec "Implement step 3 of plan/03-protocol.md"
```

Why the wrapper exists: the `[ORCH:<task-id>]` trigger is what makes each agent
enter orchestrated mode (read `.orchestration/INSTRUCTIONS.md`, honor cwd-only,
do not commit). Without the marker, the agent responds in solo mode. Sending
`cmux send` directly to an agent pane is easy to get wrong (I forgot the marker
in prior conversations and the user called it out). **Use the wrapper.**

When NOT to use the wrapper:
- Direct exploratory conversation ("what is your role?", "what do you see in X?")
- Debugging, shell command, resuming claude — solo mode is appropriate
- In those cases, use `cmux send --surface "$(surface_of <Name>)" -- "<text>"` +
  `cmux send-key --surface "$(surface_of <Name>)" enter` (separate Enter
  because `\n` becomes a multiline newline in the claude prompt, not submit)

### Wait for the worker to finish (result-file polling)

**Preferred form** — dispatch with `--wait` polls
`.orchestration/results/<task-id>.md` until it detects a new mtime. **Always run
it in the background** (Bash tool with `run_in_background: true`), so the command
appears in the Claude Code footer and **does NOT block the conversation** — you are
notified when the result file is written and can continue conversing meanwhile:

```bash
# run through Bash with run_in_background: true
scripts/cmux-dispatch.sh --wait Extension 25-wave-x "..."
# does not block the turn: runs detached, footer shows progress,
# completion notification arrives when the agent writes the result file
```

> **Why background, never foreground**: `--wait` in the foreground holds the
> entire turn (up to the default 1800s timeout) and the conversation is captive to
> the worker. With `run_in_background: true`, polling runs detached — you dispatch
> N tasks in parallel, all appear in the footer, and every completion notification
> brings you back to read the result. Use the foreground only for a single, quick
> task you deliberately want to block on (rare).

How it works: the script captures `stat -c %Y` of the file BEFORE the dispatch
(0 if it does not exist) and polls every 2s until `cur_mtime > before_mtime`,
then confirms it has a `**Status**:` line. It is hook-independent — it works
with plain claude in the panes. The default timeout is 1800s, adjustable through
`--timeout <s>` and `--poll-interval <s>`.

**Why polling instead of hooks**: hooks (`agent.hook.Stop`) are only emitted
when the pane runs `cmux claude-teams`, but our convention is panes with plain
`claude` (per-folder, with their own `.claude/settings.json` in each
subproject). Polling reuses the existing result-file convention — the agent
must write `.orchestration/results/<id>.md` at the end of every orchestrated
task (per `INSTRUCTIONS.md`), so the file is our actual "Stop".

**Re-dispatch works**: if a task-id is reused (overwriting the result file),
the `before_mtime` snapshot ensures the next write still fires — it is not
vulnerable to a pre-existing file.

**Manual form** (debugging, or if you want to see the file appear):

```bash
# in one terminal: dispatch without wait
scripts/cmux-dispatch.sh Extension 25-wave-x "..."

# in another: poll yourself
while [ ! -f .orchestration/results/25-wave-x.md ]; do sleep 2; done
cat .orchestration/results/25-wave-x.md
```

**Hooks still work if the pane uses `cmux claude-teams`** — I did not remove
anything from cmux; I only changed what our script expects. If the setup ever
uses claude-teams, `cmux events --category agent --name agent.hook.Stop` remains
valid for anyone who wants to use it.

### Create the 4 panes from scratch

If the workspace does not yet have the panes (or they were closed), use the
`scripts/cmux-bootstrap-agents.sh` script. It creates 4 panes to the right of
the current pane, stacked vertically (App → Relay → Extension → Site), renames
each surface, and dispatches `cd <subproject> && claude [--resume]`.

**You (the orchestrator) must offer to run the script when you notice the panes
are missing.** The user decides whether they want a new or resumed session — do
not guess for them. Suggested script:

> "The agent panes are not in the workspace. Do you want me to run
> `scripts/cmux-bootstrap-agents.sh`? With `--resume`, I resume the last session
> for each subproject; without the flag, it opens Claude from scratch."

Ask and wait for a response before calling the script — **never run it yourself
without explicit authorization**: it creates real panes in the user's workspace.

```bash
scripts/cmux-bootstrap-agents.sh           # new claude session in each pane
scripts/cmux-bootstrap-agents.sh --resume  # claude --resume (picker)
```

Idempotency: if the 4 panes already exist (by title), the script exits 0 without
doing anything. Mixed state (some exist, others do not) → it aborts with an
error for you to clean up manually.

### Close the 4 panes at once

When the user wants to close all 4 agents (e.g. to recreate them from scratch,
or clean the workspace), there is a companion script:

```bash
scripts/cmux-close-agents.sh
```

It locates surfaces by title (App / Relay / Extension / Site) in the current
workspace and calls `cmux close-surface` on each. Idempotent: missing names
produce a warning, not an error. Surfaces with other names (Orchestrator, View,
worktrees `✳ <task>...`) are not touched.

**Same rule as bootstrap**: you (the orchestrator) *offer* to run it; never run
it without the user's explicit authorization — the script closes real panes and
kills active claude sessions.

### Clear the context of the 4 panes (start a new feature)

To start a new feature without carrying the previous context along, **do not
recreate the panes** — just send `/clear` to each agent. `/clear` clears the
claude conversation but keeps the process alive in the same folder, with the
same model and `.claude/`. It is lighter than close+bootstrap; the opposite of
`claude --resume` (which would load the old context).

```bash
scripts/cmux-clear-agents.sh                  # clears all 4
scripts/cmux-clear-agents.sh Extension Site   # clears only these
```

`/clear` is a **solo** command (a claude built-in), not an orchestrated dispatch
— therefore the script **does not** use the `[ORCH:]` marker; it sends the
literal text + separate Enter, like the solo path. Idempotent: missing titles
produce a warning, not an error.

> **Only run with idle agents.** If an agent is in the middle of a task, `/clear`
> becomes buffer text or interrupts the work — wait for the result file (or use
> `--wait` in the dispatch) before clearing. Same courtesy rule as
> bootstrap/close: **offer**, do not run without the user's approval.

### Reactivate a session that crashed without recreating the pane

If the pane exists but only the `claude` process died, send the command directly:

```bash
sid=$(surface_of App)   # use the helper above
cmux send     --surface "$sid" "cd ~/Projects/outpost_pi/app && claude --resume"
cmux send-key --surface "$sid" enter
```

`claude --resume` presents the picker of previous sessions in that folder; choose
the most recent. Use `claude -c` to skip the picker and return directly to the
last session. **Always confirm the cwd first** — opening Claude in the wrong
folder breaks the subproject persona.

### Do not confuse these with worktrees

Eventually, extra panes named `✳ <task>...` appear — they are worktrees or
temporary sessions created by other orchestrations (e.g. `/ultrareview`,
background agents). Do not dispatch plan work to them; only the 4 named panes
above are canonical for the planning flow.

## Report cmux progress

cmux accepts visual workspace progress through:

- `cmux set-progress <0.0-1.0> --label <text>` — progress bar
- `cmux clear-progress` — clears it
- `cmux set-status <key> <value> [--icon <name>] [--color <#hex>]` — named status

Because we have explicit planning in `plan/`, derive progress from the
**Definition of Done** checkboxes in every plan:

```bash
# run from the monorepo root
done=$(grep -h "^- \[x\]" plan/*.md | wc -l | tr -d ' ')
total=$(grep -hE "^- \[(x| )\]" plan/*.md | wc -l | tr -d ' ')
pct=$(LC_NUMERIC=C awk "BEGIN { printf \"%.3f\", $done / $total }")  # LC_NUMERIC=C avoids commas in BR locales
cmux set-progress "$pct" --label "Outpost-Pi · $done/$total tasks"
```

**When to update**:
- After marking a `[x]` in a DoD
- After adding a new plan (the total grows, percentage naturally falls)
- After completing an entire plan: `cmux set-status plan "0N complete" --color "#22c55e"`

**When to clear**:
- When all MVP plans close: `cmux clear-progress`

Do not keep calling `set-progress` every turn — only when real state changes.

## `claude-cmux` skill

For anything beyond basic `set-progress` — dispatch between panes, listening for
`agent.hook.Stop`, notifications, the `.orchestration/` pattern — use the
[`claude-cmux`](file:///Users/jacob/.claude/skills/claude-cmux/SKILL.md) skill.

It covers:
- CLI essentials (`send`, `send-key`, `events`, `notify`, `tree`, `list-panes`)
- Automatic variables (`$CMUX_WORKSPACE_ID`, `$CMUX_SURFACE_ID`)
- Orchestration pattern with `INSTRUCTIONS.md` / `plan.md` / `tasks/` / `results/`
- How to use `claude-teams` to emit structured hooks

The skill automatically triggers for cmux questions or parallel-orchestration
requests. Do not duplicate its content here — invoke the skill.
