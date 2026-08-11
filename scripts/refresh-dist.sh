#!/usr/bin/env bash
# refresh-dist.sh — rebuild the outpost-pi extension dist/ and restart every
# wrapped agent WITH --continue so they pick up the new code (sessions resumed).
#
# Mobile-managed dist refresh: from the phone you tell the orchestrator agent to
# run this; it rebuilds once and hot-reloads every agent. Turn-aware: skips any
# agent that is mid-turn (working) — nothing is interrupted. The orchestrator
# running this script restarts itself LAST via the hot-reload arm (fires at
# agent_settled, the SDK idle boundary), so its own turn completes first.
#
# Agents must already be under the wrapper (run wrap-agents.sh once). Bare agents
# are skipped with a warning. Relay redeploy is separate (docker).

set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"
ROOT="/home/agent/projects/outpost_pi"
REMOTE="${OUTPOST_PI_HOME:-$HOME/.pi/remote}"

echo "=== rebuild dist/ ==="
( cd "$ROOT/pi-extension" && ./node_modules/.bin/tsc ) || { echo "BUILD FAILED — aborting (no agents touched)"; exit 1; }
echo "dist rebuilt: $(stat -c %y "$ROOT/pi-extension/dist/index.js" | cut -d. -f1)"
echo ""
echo "=== restart wrapped agents with --continue ==="

python3 - "$ROOT" "$REMOTE" <<'PY'
import json, subprocess, sys, time, os
ROOT, REMOTE = sys.argv[1], sys.argv[2]

def run(*a):
    return subprocess.run(a, capture_output=True, text=True)

def pane_info(pane):
    try:
        d = json.loads(run('herdr', 'pane', 'process-info', '--pane', pane).stdout)
        return d['result']['process_info']
    except Exception:
        return None

def is_wrapped(procs):
    return any('pi-restart-loop' in (p.get('cmdline') or '') for p in procs)

def pi_pid_of(procs):
    return next((p.get('pid') for p in procs if p.get('name') == 'pi'), None)

def comm_of(pid):
    try: return open(f'/proc/{pid}/comm').read().strip()
    except Exception: return ''

def ppid_of(pid):
    try:
        for line in open(f'/proc/{pid}/status'):
            if line.startswith('PPid:'):
                return int(line.split()[1])
    except Exception: pass
    return None

def my_pi_pid():
    """Walk up from this process to find the pi ancestor (the orchestrator)."""
    p = os.getppid()
    seen = set()
    while p and p not in seen:
        seen.add(p)
        if comm_of(p) == 'pi':
            return p
        p = ppid_of(p)
    return None

me = my_pi_pid()
print(f'[self] orchestrator pi pid = {me}')

panes = json.loads(run('herdr', 'pane', 'list').stdout).get('result', {}).get('panes', [])
restarted = skipped_bare = skipped_busy = 0
failed = []
my_pane = None
for p in panes:
    cwd = p.get('cwd', '')
    if '/home/agent/projects/' not in cwd:
        continue
    pane = p.get('pane_id')
    label = p.get('workspace_id', '?')
    status = p.get('agent_status', '?')
    info = pane_info(pane) or {}
    procs = info.get('foreground_processes', [])
    pid = pi_pid_of(procs)
    if pid == me:
        my_pane = (label, pane)
        print(f'[self] {label:<6} orchestrator — will hot-reload-arm last')
        continue
    if not is_wrapped(procs):
        print(f'[skip] {label:<6} not wrapped (run wrap-agents.sh first)')
        skipped_bare += 1
        continue
    if status == 'working':
        print(f'[skip] {label:<6} WORKING — defer')
        skipped_busy += 1
        continue
    if not pid:
        print(f'[skip] {label:<6} no pi pid')
        failed.append(label)
        continue
    print(f'[hot]  {label:<6} ({pane}, pid {pid}) marker + SIGTERM → --continue')
    open(f'{REMOTE}/.restart-marker-{pid}', 'w').close()
    run('kill', '-TERM', str(pid))
    ok = False
    for _ in range(20):
        time.sleep(2)
        if pi_pid_of((pane_info(pane) or {}).get('foreground_processes', [])):
            ok = True
            break
    if ok:
        print(f'  \u2713 {label} restarted with --continue')
        restarted += 1
    else:
        print(f'  \u2717 {label} did not come back')
        failed.append(label)

print()
print(f'restarted={restarted}  skipped_bare={skipped_bare}  deferred_busy={skipped_busy}  failed={failed}')

# Orchestrator restarts itself last, at agent_settled, so this turn finishes first.
if my_pane:
    label, pane = my_pane
    print(f'\n[self] arming hot-reload for orchestrator ({label}) — fires at next agent_settled')
    r1 = run('bash', f'{ROOT}/scripts/hot-reload.sh', 'on')
    r2 = run('bash', f'{ROOT}/scripts/hot-reload.sh', 'arm')
    print(f'  on:  {r1.stdout.strip() or r1.stderr.strip()[:80]}')
    print(f'  arm: {r2.stdout.strip() or r2.stderr.strip()[:80]}')
    print('  (orchestrator will pick up the new dist after this turn settles)')
else:
    print('\n[self] orchestrator not found among panes — restart it manually if needed')
PY
