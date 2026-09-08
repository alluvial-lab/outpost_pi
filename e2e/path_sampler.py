#!/usr/bin/env python3
"""Phone-path telemetry sampler (metronome verdict #6: WHO severs the tunnel).

Runs entirely on the VM. Three streams into one JSONL:

  1. every 10s: `tailscale status --json` projection for the phone peer —
     endpoint (CurAddr), DERP relay choice, byte counters, last handshake.
     A strike whose teardown coincides with an endpoint/path flip on this
     side means the phone's underlay path changed at that moment (phone or
     router side); a strike with a STABLE endpoint here points at the
     phone's tailscale app tearing down internally.
  2. relay log follow: every `stream error` / relay-initiated close row for
     any peer (carries frames_out/out_hash — the instrument).
  3. tailscaled log follow: link changes / rebinds / magicsock events
     (VM-side tunnel events — the docker-bridge-churn rebind class).

Correlate offline by timestamp. Usage:
  python3 e2e/path_sampler.py [--phone-ip <redacted phone tailnet addr>] [--out FILE] \
      [--poll-s 10] [--duration-min 0]
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def strip_ansi(line: str) -> str:
    import re

    return re.sub(r"\x1b\[[0-9;]*m", "", line)


class Follower(threading.Thread):
    """Follow `docker logs -f` for one container, filtering to a regex."""

    def __init__(self, container: str, pattern, out, kind: str, since: str = "60m"):
        super().__init__(daemon=True)
        self.container = container
        self.pattern = pattern
        self.out = out
        self.kind = kind
        self.since = since

    def run(self) -> None:
        cmd = ["docker", "logs", "-f", "--since", self.since, self.container]
        while True:
            try:
                proc = subprocess.Popen(
                    cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
                )
                for line in proc.stdout:
                    line = strip_ansi(line).rstrip()
                    if self.pattern.search(line):
                        self.out.write({"ev": self.kind, "line": line})
            except Exception as exc:  # noqa: BLE001 - sampler must survive
                self.out.write({"ev": "error", "src": self.kind, "err": str(exc)})
                time.sleep(5)


class Writer:
    def __init__(self, path: Path):
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._fh = open(self.path, "a", encoding="utf-8")
        self._lock = threading.Lock()

    def write(self, obj: dict) -> None:
        with self._lock:
            self._fh.write(json.dumps({"t": now_iso(), **obj}, default=str) + "\n")
            self._fh.flush()


def phone_projection(status: dict, phone_ip: str) -> dict | None:
    peer = None
    # Newer tailscale: {"PeerMap": {nodeKey: {...}}}; older: {"Peer": {...}}
    container = status.get("PeerMap") or status.get("Peer") or {}
    if isinstance(container, dict):
        for entry in container.values():
            addrs = entry.get("Addrs") or []
            if any(phone_ip in (a or "") for a in addrs) or entry.get("TailscaleIPs", [None])[0] == phone_ip:
                peer = entry
                break
    if peer is None:
        return None
    return {
        "host": peer.get("HostName"),
        "online": peer.get("Online"),
        "active": peer.get("Active"),
        "curAddr": peer.get("CurAddr"),
        "addrs": peer.get("Addrs"),
        "relay": peer.get("Relay"),
        "rxBytes": peer.get("RxBytes"),
        "txBytes": peer.get("TxBytes"),
        "lastHandshake": peer.get("LastHandshake"),
        "lastSeen": peer.get("LastSeen"),
        "keepAlive": peer.get("KeepAlive"),
    }


def main() -> int:
    import re

    ap = argparse.ArgumentParser()
    ap.add_argument("--phone-ip", default="<redacted phone tailnet addr>")
    ap.add_argument("--out", default=None)
    ap.add_argument("--poll-s", type=float, default=10.0)
    ap.add_argument("--duration-min", type=float, default=0.0)
    args = ap.parse_args()

    out_path = Path(args.out) if args.out else HERE / ".run-state" / "severance" / (
        f"path-sampler-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.jsonl"
    )
    writer = Writer(out_path)
    writer.write({"ev": "header", "phoneIp": args.phone_ip, "pollS": args.poll_s, "out": str(out_path)})
    print(f"[{now_iso()}] path sampler -> {out_path} (phone {args.phone_ip})", flush=True)

    Follower(
        "outpost-pi-relay",
        re.compile(r"stream error|relay initiated peer socket close|authenticated peer|disconnected peer"),
        writer,
        "relay",
        since="0m",
    ).start()
    Follower(
        "tailscale",
        re.compile(r"LinkChange|Rebind|magicsock|netmap|peer|endpoint"),
        writer,
        "tailscaled",
        since="0m",
    ).start()

    deadline = time.time() + args.duration_min * 60 if args.duration_min > 0 else None
    last_bytes = None
    while True:
        if deadline and time.time() > deadline:
            writer.write({"ev": "end", "reason": "duration"})
            return 0
        try:
            raw = subprocess.run(
                ["docker", "exec", "tailscale", "tailscale", "status", "--json"],
                capture_output=True, text=True, timeout=15,
            )
            if raw.returncode == 0:
                status = json.loads(raw.stdout)
                proj = phone_projection(status, args.phone_ip)
                cur = (proj or {}).get("rxBytes")
                delta = None if cur is None or last_bytes is None else cur - last_bytes
                last_bytes = cur
                writer.write({"ev": "phone", "peer": proj, "rxDelta10s": delta})
            else:
                writer.write({"ev": "error", "src": "status", "err": raw.stderr.strip()[:200]})
        except Exception as exc:  # noqa: BLE001
            writer.write({"ev": "error", "src": "poll", "err": str(exc)})
        time.sleep(args.poll_s)


if __name__ == "__main__":
    sys.exit(main())
