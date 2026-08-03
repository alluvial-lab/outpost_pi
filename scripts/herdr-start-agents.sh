#!/usr/bin/env bash
# herdr-start-agents.sh — start pi agents in existing Herdr workspaces.
#
# The workspaces are already created (w3-wE from herdr-setup.sh). This script
# starts pi in each pane. Run from a shell outside the Herdr TUI.

set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

# Map workspace labels to pane IDs (from the herdr-setup.sh creation output).
# For outpost, use the wrapper; for others, use herdr agent start --kind pi.
declare -A WRAPPER=( [outpost]=1 )

# Get all panes with their workspace labels
panes_json=$(herdr pane list --json 2>/dev/null)

# Parse and start agents
echo "$panes_json" | python3 -c "
import sys, json, subprocess

panes = json.load(sys.stdin)
for p in panes:
    ws = p.get('workspace_label', p.get('workspace_id', ''))
    pane_id = p['id']
    cwd = p.get('cwd', '')
    label = ws

    # Skip workspaces without a known project cwd
    if not cwd or '/home/agent/projects/' not in cwd:
        continue

    use_wrapper = label == 'outpost'
    print(f'[herdr-start] {label} ({pane_id}, {cwd})')

    if use_wrapper:
        # outpost: send the wrapper command to the pane
        cmd = f\"cd {cwd} && ./scripts/pi-restart-loop.sh\"
        result = subprocess.run(
            ['herdr', 'pane', 'send-text', pane_id, cmd + '\n'],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            print(f'  ✓ started pi under wrapper')
        else:
            print(f'  ✗ send-text failed: {result.stderr.strip()[:80]}')
    else:
        # Others: start as managed agent
        result = subprocess.run(
            ['herdr', 'agent', 'start', label, '--kind', 'pi', '--pane', pane_id, '--', '--continue'],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            print(f'  ✓ started pi as managed agent')
        else:
            # Fallback: send pi --continue as text
            subprocess.run(['herdr', 'pane', 'send-text', pane_id, 'pi --continue\n'],
                          capture_output=True, text=True)
            print(f'  ~ agent start failed, sent pi --continue as text')
" 2>&1

echo "[herdr-start] done. Run 'herdr' to see agents in the sidebar."
