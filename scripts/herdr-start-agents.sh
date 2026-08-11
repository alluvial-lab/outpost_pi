#!/usr/bin/env bash
# herdr-start-agents.sh — start pi agents in existing Herdr workspaces.
#
# COLD start: assumes each project pane is sitting at a bash prompt (no pi
# running). Launches the pi-restart-loop wrapper in every project pane.
#
# Every agent runs under the wrapper (cwd-parameterized) so mobile /new and
# hot-reload dist-refresh work on any session. Agents are discovered DYNAMICALLY
# from `herdr pane list` — add/remove project panes freely; new ones auto-wrap.
#
# To convert ALREADY-RUNNING bare-pi agents to wrapped (without a full restart),
# use wrap-agents.sh (turn-aware). Run this script from outside the Herdr TUI.

set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

WRAPPER_SCRIPT="/home/agent/projects/outpost_pi/scripts/pi-restart-loop.sh"

herdr pane list | python3 -c "
import sys, json, subprocess
WRAPPER = '$WRAPPER_SCRIPT'
panes = json.load(sys.stdin).get('result', {}).get('panes', [])
for p in panes:
    cwd = p.get('cwd', '')
    if not cwd or '/home/agent/projects/' not in cwd:
        continue
    pane_id = p.get('pane_id')
    label = p.get('workspace_id', '?')
    print(f'[herdr-start] {label} ({pane_id}, {cwd})')
    cmd = f\"cd {cwd} && bash {WRAPPER}\"
    result = subprocess.run(
        ['herdr', 'pane', 'send-text', pane_id, cmd + '\n'],
        capture_output=True, text=True,
    )
    if result.returncode == 0:
        print(f'  \u2713 started pi under wrapper')
    else:
        print(f'  \u2717 send-text failed: {result.stderr.strip()[:80]}')
" 2>&1

echo "[herdr-start] done. Run 'herdr' to see agents in the sidebar."
