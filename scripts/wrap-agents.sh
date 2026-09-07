#!/usr/bin/env bash
# wrap-agents.sh — cycle already-running BARE-pi agents under the restart wrapper.
#
# Turn-aware: skips any agent whose agent_status is "working" (never interrupts a
# running turn). Idempotent: skips agents already under the wrapper. Dynamic:
# discovers all project panes at runtime, so it catches agents added since the
# last run (count is irrelevant).
#
# For each bare, non-working agent: graceful SIGTERM to pi → pane returns to bash
# → relaunch the wrapper → pi resumes with --continue under the wrapper.
# herdr does not supervise/auto-restart agents, so this is safe.
#
# Re-run any time to pick up newly-added or newly-idle agents.

set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"
WRAPPER="/home/agent/projects/outpost_pi/scripts/pi-restart-loop.sh"

python3 - "$WRAPPER" <<'PY'
import json, os, subprocess, sys, time
WRAPPER = sys.argv[1]

# Self-exclusion: never wrap (i.e. never SIGTERM) the pane of the pi that is
# RUNNING this script. Ancestry detection breaks under setsid/nohup detachment,
# so the RELIABLE channel is explicit: set WRAP_EXCLUDE_PANE=<pane_id> (and/or
# WRAP_EXCLUDE_CWD=<cwd>) when launching. Ancestor-pid detection remains as a
# fallback for attached runs. Without exclusion, a run from inside a fleet pi
# kills its own executor first (observed 2026-09-07: zero-output runs + session loss).
EXCLUDE_PANE = os.environ.get("WRAP_EXCLUDE_PANE", "")
EXCLUDE_CWD = os.environ.get("WRAP_EXCLUDE_CWD", "")

def ancestor_pids():
    pids = set()
    p = os.getppid()
    while p > 1:
        pids.add(p)
        try:
            with open(f"/proc/{p}/stat") as f:
                p = int(f.read().split(')')[-1].split()[1])
        except Exception:
            break
    return pids

SELF_PIDS = ancestor_pids()

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

panes = json.loads(run('herdr', 'pane', 'list').stdout)
panes = panes.get('result', {}).get('panes', [])

wrapped_n = skipped_wrapped = skipped_busy = 0
failed = []
for p in panes:
    cwd = p.get('cwd', '')
    if '/home/agent/projects/' not in cwd:
        continue
    pane = p.get('pane_id')
    label = p.get('workspace_id', '?')
    status = p.get('agent_status', '?')
    info = pane_info(pane) or {}
    procs = info.get('foreground_processes', [])
    if is_wrapped(procs):
        print(f'[skip] {label:<6} already wrapped')
        skipped_wrapped += 1
        continue
    if status == 'working':
        print(f'[skip] {label:<6} WORKING (mid-turn) — defer; re-run later')
        skipped_busy += 1
        continue
    if pane == EXCLUDE_PANE or (EXCLUDE_CWD and cwd == EXCLUDE_CWD):
        print(f'[skip] {label:<6} SELF (explicit exclusion) — excluded')
        continue
    pid = pi_pid_of(procs)
    if pid and pid in SELF_PIDS:
        print(f'[skip] {label:<6} SELF (executor pane) — excluded')
        continue
    if not pid:
        print(f'[skip] {label:<6} no pi pid found')
        failed.append(label)
        continue
    print(f'[wrap] {label:<6} ({pane}, pid {pid}, {status}) → SIGTERM + relaunch')

    run('kill', '-TERM', str(pid))

    # poll for pi (and any wrapper) to clear → pane back at its shell
    gone = False
    for _ in range(25):
        time.sleep(1)
        procs2 = (pane_info(pane) or {}).get('foreground_processes', [])
        if not any(pr.get('name') == 'pi' for pr in procs2) and not is_wrapped(procs2):
            gone = True
            break
    if not gone:
        print(f'  \u2717 {label} pi did not exit — aborting this agent')
        failed.append(label)
        continue

    run('herdr', 'pane', 'send-text', pane, f'cd {cwd} && bash {WRAPPER}\n')

    # verify wrapper + pi came back
    ok = False
    for _ in range(20):
        time.sleep(2)
        procs3 = (pane_info(pane) or {}).get('foreground_processes', [])
        if is_wrapped(procs3) and pi_pid_of(procs3):
            ok = True
            break
    if ok:
        print(f'  \u2713 {label} wrapped')
        wrapped_n += 1
    else:
        print(f'  \u2717 {label} did not come back under wrapper')
        failed.append(label)

print()
print(f'DONE: wrapped={wrapped_n}  already_wrapped={skipped_wrapped}  '
      f'deferred_busy={skipped_busy}  failed={failed}')
if skipped_busy:
    print('Re-run later to pick up the deferred (busy) agents once they are idle.')
PY
