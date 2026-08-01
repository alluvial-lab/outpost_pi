#!/usr/bin/env bash
# herdr-setup.sh — create Herdr workspaces for each project and start pi agents.
#
# Run this AFTER starting the Herdr server (`herdr`) and from a separate shell
# (not inside the Herdr TUI). Quit existing pi sessions first to avoid
# RoomAlreadyOpenError.
#
# Usage:
#   ssh agent@<lan-ip>       # or Tailscale IP
#   herdr                           # start the server (Ctrl+b q to detach)
#   ./scripts/herdr-setup.sh        # run this from another shell
#   herdr                           # reattach to see the workspaces

set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

# Define projects: label|cwd|use_wrapper (1=outpost wrapper, 0=plain pi)
PROJECTS=(
  "outpost|/home/agent/projects/outpost_pi|1"
  "patchbay|/home/agent/projects/patchbay|0"
  "snc-video|/home/agent/projects/SNC/video|0"
)

echo "[herdr-setup] creating workspaces + starting agents..."

for entry in "${PROJECTS[@]}"; do
  IFS='|' read -r label cwd use_wrapper <<< "$entry"
  if [ ! -d "$cwd" ]; then
    echo "[herdr-setup] skip $label — $cwd does not exist"
    continue
  fi
  echo "[herdr-setup] workspace: $label ($cwd)"

  # Create the workspace (each gets w<N>:p1 — a shell pane at the cwd)
  herdr workspace create --cwd "$cwd" --label "$label" 2>/dev/null || {
    echo "[herdr-setup]   workspace already exists or failed — skipping"
    continue
  }

  # Get the pane ID for this workspace's first pane
  # Herdr assigns w1:p1, w2:p1, etc. in creation order
  pane_id=$(herdr pane list --json 2>/dev/null | \
    python3 -c "
import sys, json
panes = json.load(sys.stdin)
for p in panes:
    if p.get('workspace_label') == '$label':
        print(p['id']); break
" 2>/dev/null || echo "")

  if [ -z "$pane_id" ]; then
    echo "[herdr-setup]   could not find pane for $label — start pi manually"
    continue
  fi

  if [ "$use_wrapper" = "1" ] && [ -f "$cwd/scripts/pi-restart-loop.sh" ]; then
    # outpost_pi: run the wrapper (for hot-reload restart support)
    echo "[herdr-setup]   starting pi under wrapper in $pane_id"
    herdr pane send-text "$pane_id" "cd $cwd && ./scripts/pi-restart-loop.sh\n" 2>/dev/null
  else
    # Other projects: start pi directly as a managed agent
    echo "[herdr-setup]   starting pi as managed agent in $pane_id"
    herdr agent start "$label" --kind pi --pane "$pane_id" -- --continue 2>/dev/null || {
      echo "[herdr-setup]   agent start failed — try: herdr pane send-text $pane_id 'pi --continue\n'"
    }
  fi
done

echo "[herdr-setup] done. Run 'herdr' to attach and see the workspaces."
echo "[herdr-setup] Sidebar shows agent state: working/idle/blocked/done."
