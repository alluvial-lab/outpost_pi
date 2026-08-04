#!/usr/bin/env bash
# herdr-restart-agents.sh — gracefully restart pi agents in Herdr workspaces so
# each reloads the rebuilt extension dist/ (ESM — pi's /reload CANNOT load it;
# only a full process restart picks up new dist/ code).
#
# Mirrors herdr-start-agents.sh: the `outpost` workspace runs under the
# pi-restart-loop.sh wrapper; the others are `herdr agent start --kind pi`. This
# script sends `/quit` to each pane, waits for pi to exit, then relaunches in the
# same pane with `--continue` (sessions resume; only the extension reloads).
#
# Usage:
#   ./scripts/herdr-restart-agents.sh                 # restart all EXCEPT outpost
#   ./scripts/herdr-restart-agents.sh --all           # include outpost too
#   ./scripts/herdr-restart-agents.sh --only w5,w6    # restart only these workspace ids
#   ./scripts/herdr-restart-agents.sh --skip w3,w4    # restart all except these
#   ./scripts/herdr-restart-agents.sh --dry-run       # show what would happen
#
# ⚠️ The workspace running THIS session is `outpost` (w3). Restarting it exits
# the current conversation. The default skips it; use --all or `--only w3`
# deliberately (expect this session to end + reconnect after relaunch).
#
# Reusable: run this after every `dist/` rebuild to put every agent on the new
# extension without re-pairing (the wire schema change is additive/optional).

set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

WRAPPERS=(outpost_pi)    # project cwd suffixes that run under pi-restart-loop.sh
QUIT_WAIT_S=4             # grace seconds after /quit for an idle pi to exit
POLL_DEADLINE_S=15        # max seconds to wait for pi to actually exit

ONLY=()
SKIP=()
ALL=0
DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)    ALL=1; shift;;
    --only)   IFS=',' read -ra ONLY <<< "$2"; shift 2;;
    --skip)   IFS=',' read -ra SKIP <<< "$2"; shift 2;;
    --dry-run) DRY=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

# Default skip list: the interactive outpost session (this conversation lives there).
if [[ $ALL -eq 0 && ${#SKIP[@]} -eq 0 && ${#ONLY[@]} -eq 0 ]]; then
  SKIP=(w3)
fi

export R_ONLY="$(IFS=,; echo "${ONLY[*]}")"
export R_SKIP="$(IFS=,; echo "${SKIP[*]}")"
export QUIT_WAIT_S POLL_DEADLINE_S
export PANES_JSON="$(herdr pane list 2>/dev/null || true)"

python3 - "$DRY" "${WRAPPERS[@]}" <<'PY'
import json, os, subprocess, sys, time

dry = sys.argv[1] == "1"
wrappers = set(sys.argv[2:])

only = set(x for x in os.environ.get("R_ONLY","").split(",") if x)
skip = set(x for x in os.environ.get("R_SKIP","").split(",") if x)
quit_wait = int(os.environ.get("QUIT_WAIT_S","4"))
poll_deadline = int(os.environ.get("POLL_DEADLINE_S","15"))

def run(args, **kw):
    return subprocess.run(args, capture_output=True, text=True, **kw)

def pane_still_running_pi(pane_id):
    r = run(["herdr","agent","list","--json"])
    if r.returncode != 0:
        return True
    try:
        data = json.loads(r.stdout)
        agents = data.get("result",{}).get("agents",[]) if isinstance(data, dict) else data
    except Exception:
        return True
    return any(a.get("pane_id") == pane_id for a in agents)

try:
    raw = json.loads(os.environ.get("PANES_JSON","[]"))
except Exception as e:
    print(f"failed to parse `herdr pane list`: {e}", file=sys.stderr)
    sys.exit(1)
if isinstance(raw, dict):
    res = raw.get("result", raw)
    panes = res.get("panes", []) if isinstance(res, dict) else res
else:
    panes = raw
for p in panes:
    ws   = p.get("workspace_id","")
    label= p.get("workspace_label") or ws
    pane = p.get("pane_id") or p.get("id","")
    cwd  = p.get("cwd","")
    if not cwd or "/home/agent/projects/" not in cwd:
        continue
    if only and ws not in only:
        continue
    if skip and ws in skip:
        print(f"[skip] {label} ({ws}) — in skip list")
        continue

    use_wrapper = any(cwd.rstrip("/").endswith(w) for w in wrappers)
    print(f"[restart] {label} ({ws}, pane {pane}, cwd {cwd}, wrapper={use_wrapper})")

    if dry:
        print("  (dry-run) would: /quit → wait exit → relaunch " +
              ("./scripts/pi-restart-loop.sh" if use_wrapper else "herdr agent start --continue"))
        continue

    # 1) graceful quit
    run(["herdr","pane","send-text", pane, "/quit\n"])
    # 2) wait for pi to actually exit
    deadline = time.time() + poll_deadline
    while time.time() < deadline:
        time.sleep(1)
        if not pane_still_running_pi(pane):
            break
    else:
        print(f"  ⚠ {label}: pi still running after {poll_deadline}s — sending Ctrl-C")
        run(["herdr","pane","send-text", pane, "C-c"])  # best-effort; herdr may need literal C-c
        time.sleep(quit_wait)
    # 3) relaunch in the same pane
    if use_wrapper:
        cmd = f"cd {cwd} && ./scripts/pi-restart-loop.sh\n"
        r = run(["herdr","pane","send-text", pane, cmd])
    else:
        r = run(["herdr","agent","start", ws, "--kind","pi","--pane", pane, "--","--continue"])
    print(f"  {'✓' if r.returncode==0 else '✗'} relaunch rc={r.returncode}" +
          (f" ({r.stderr.strip()[:80]})" if r.returncode else ""))
PY
