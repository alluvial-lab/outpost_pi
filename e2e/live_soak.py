#!/usr/bin/env python3
"""Run a reproducible live-device chaos soak and triage its capture ring.

The scheduler is deliberately independent from the device runner.  It can be
unit-tested without Docker, adb, Flutter, or an emulator; the device path
materializes the same schedule as a temporary integration test and runs it
through ``run-live.sh``.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import subprocess
import sys
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

ROOT = Path(__file__).resolve().parent.parent
RUNNER = ROOT / "e2e" / "run-live.sh"
TRIAGE = ROOT / "scripts" / "debug_capture_triage.py"
DEFAULT_DURATION_SECONDS = 10 * 60
DEFAULT_SEED = 20260821
MIN_HOLD_SECONDS = 2
MAX_HOLD_SECONDS = 60

KNOWN_FINDINGS = {
    "swallow": "story-app-send-swallowed-session-identity-unavailable",
    "blank_chat": "backlog-app-blank-chat-direct-open",
}

FAULT_CLASSES = ("timeout", "slicer", "down")
FAULT_WEIGHTS = (
    ("net_fault", 22),
    ("relay_pause", 12),
    ("pi_restart", 12),
    ("app_background", 10),
    ("app_airplane", 10),
)
ACTION_WEIGHTS = (("send", 20), ("navigation", 9), ("cold_restart", 5))


@dataclass(frozen=True)
class ScheduleEvent:
    """One serialized action in the monotonic soak schedule."""

    at_seconds: int
    kind: str
    name: str
    hold_seconds: int = 0
    command: str | None = None
    clear_command: str | None = None

    def as_json(self) -> dict[str, Any]:
        return asdict(self)


def _weighted_choice(rng: random.Random, weights: Iterable[tuple[str, int]]) -> str:
    names = [name for name, _ in weights]
    return rng.choices(names, weights=[weight for _, weight in weights], k=1)[0]


def _fault_event(rng: random.Random, at: int, remaining: int) -> ScheduleEvent:
    name = _weighted_choice(rng, FAULT_WEIGHTS)
    hold = rng.randint(MIN_HOLD_SECONDS, min(MAX_HOLD_SECONDS, remaining))
    if name == "net_fault":
        fault_class = rng.choice(FAULT_CLASSES)
        # The toxic duration is intentionally shorter than the hold for most
        # events: it exercises timeout/slicer behavior without making a whole
        # schedule unrecoverable.
        timeout_ms = rng.randint(500, 8_000)
        return ScheduleEvent(
            at_seconds=at,
            kind="fault",
            name=f"net_{fault_class}",
            hold_seconds=hold,
            command=f"net_fault {fault_class} {timeout_ms}",
            clear_command="net_clear",
        )
    if name == "relay_pause":
        return ScheduleEvent(at, "fault", name, hold, "relay_pause", "relay_resume")
    if name == "pi_restart":
        return ScheduleEvent(at, "fault", name, hold, "pi_restart", None)
    if name == "app_background":
        return ScheduleEvent(at, "fault", name, hold, "app_background", "app_foreground")
    return ScheduleEvent(at, "fault", name, hold, "app_airplane on", "app_airplane off")


def build_schedule(seed: int, duration_seconds: int) -> tuple[ScheduleEvent, ...]:
    """Build a bounded, deterministic schedule for one soak duration.

    ``random.Random`` is local and seeded, so this function does not mutate
    process-global randomness.  Fault holds are always 2--60 seconds and
    events never overlap; the serialized schedule is therefore a replay key.
    """
    if duration_seconds < MIN_HOLD_SECONDS:
        raise ValueError("duration must be at least 2 seconds")

    rng = random.Random(seed)
    events: list[ScheduleEvent] = []
    cursor = 0
    # Keep the two still-open reproducer paths in every normal soak. They are
    # deliberately ordinary device actions, not hidden assertions: the oracle
    # must report them when the corresponding product bug is still present.
    if duration_seconds >= 34:
        events.extend(
            (
                ScheduleEvent(5, "action", "send"),
                ScheduleEvent(15, "fault", "net_down", 3, "net_fault down", "net_clear"),
                ScheduleEvent(18, "action", "send_identity_window"),
                ScheduleEvent(28, "action", "navigation"),
            )
        )
        cursor = 34
    while cursor < duration_seconds:
        gap = rng.randint(2, min(15, duration_seconds - cursor))
        cursor += gap
        if cursor >= duration_seconds:
            break
        remaining = duration_seconds - cursor
        if remaining < MIN_HOLD_SECONDS:
            break
        if rng.random() < 0.59:
            event = _fault_event(rng, cursor, remaining)
            cursor += event.hold_seconds
        else:
            name = _weighted_choice(rng, ACTION_WEIGHTS)
            event = ScheduleEvent(cursor, "action", name)
        events.append(event)
    return tuple(events)


def schedule_fingerprint(schedule: Iterable[ScheduleEvent]) -> str:
    """Return a stable JSON representation suitable for reports and replay."""
    return json.dumps(
        [event.as_json() for event in schedule],
        sort_keys=True,
        separators=(",", ":"),
    )


def _dart_schedule(schedule: tuple[ScheduleEvent, ...]) -> str:
    # JSON object/list syntax is also valid Dart collection literal syntax.
    return json.dumps([event.as_json() for event in schedule], separators=(",", ":"))


def _generated_test(schedule: tuple[ScheduleEvent, ...], timeout_seconds: int) -> str:
    encoded = _dart_schedule(schedule)
    return f'''@Tags(['e2e'])
library;

import 'dart:async';

import 'package:app/data/transport/connection_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/live_device_harness.dart';

const _schedule = <Map<String, Object?>>{encoded};

void main() {{
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('seeded live oddities soak', (tester) async {{
    final parentZone = Zone.current;
    await runZonedGuarded(() async {{
      final harness = await LiveDeviceHarness.create(restorePair: false);
      try {{
        await harness.pair(tester);
        await harness.mountChat(tester);
        final clock = Stopwatch()..start();
        for (final event in _schedule) {{
          final target = Duration(
            milliseconds: ((event['at_seconds']! as num) * 1000).round(),
          );
          while (clock.elapsed < target) {{
            await tester.pump(const Duration(milliseconds: 100));
          }}
          await _runEvent(tester, harness, event);
        }}
      }} finally {{
        await harness.close(tester);
      }}
    }}, (error, stack) {{
      // A hard network fault can surface one asynchronous handshake error
      // after connChannelLost. The capture ring is the oracle for that
      // intentional fault; preserve all unrelated test errors.
      if (error.runtimeType.toString() == 'WebSocketChannelException') {{
        debugPrintSynchronously('SOAK_EXPECTED_TRANSPORT_ERROR');
        return;
      }}
      parentZone.handleUncaughtError(error, stack);
    }});
  }}, timeout: const Timeout(Duration(seconds: {timeout_seconds})));
}}

Future<void> _runEvent(
  WidgetTester tester,
  LiveDeviceHarness harness,
  Map<String, Object?> event,
) async {{
  final kind = event['kind'];
  if (kind == 'fault') {{
    requestLiveFault(event['command']! as String);
    final hold = event['hold_seconds']! as int;
    if (event['name'] == 'app_background') {{
      // Flutter's live binding may stop scheduling frames while the real app
      // is backgrounded; the host fault loop still needs wall-clock progress
      // to deliver the paired foreground request.
      await Future<void>.delayed(Duration(seconds: hold));
    }} else {{
      for (var elapsed = 0; elapsed < hold; elapsed++) {{
        await tester.pump(const Duration(seconds: 1));
      }}
    }}
    final clear = event['clear_command'];
    // Quiesce the production retry loop before restoring a proxy that was
    // intentionally hard-downed. This is the same bounded reconnect boundary
    // used by the verified live infrastructure lane and avoids an unhandled
    // handshake exception racing the test teardown.
    if (clear is String &&
        (event['name'] == 'net_down' || event['name'] == 'net_timeout' ||
            event['name'] == 'net_slicer' || event['name'] == 'relay_pause')) {{
      await harness.connection.disconnect();
    }}
    if (clear is String) requestLiveFault(clear);
    if (clear != null || event['name'] == 'pi_restart') {{
      if (event['name'] == 'net_down') {{
        // Deliberately overlap the reconnect handshake and send. This is the
        // checked-in reproducer for the identity-window tracking item.
        final reconnecting = harness.connection.connectTo(harness.peer);
        await harness.sync.sendMessage(
          'live soak identity-window probe ${{event['at_seconds']}}',
        );
        await reconnecting;
      }} else {{
        await harness.connection.connectTo(harness.peer);
      }}
      await harness.waitOnlineAndLive(tester: tester);
    }}
    return;
  }}
  switch (event['name']) {{
    case 'send':
      // Rebuild the route after background/airplane cycles so this user action
      // exercises the production cold projection path rather than depending
      // on a stale widget tree.
      await harness.unmountChat(tester);
      await harness.mountChat(tester);
      await harness.waitOnlineAndLive(tester: tester);
      final index = event['at_seconds'];
      await harness.sendAndResolve(
        tester,
        prompt: 'live soak prompt $index',
        reply: 'live soak reply $index',
      );
    case 'send_identity_window':
      await harness.sync.sendMessage(
        'live soak identity-window probe ${{event['at_seconds']}}',
      );
      await tester.pump(const Duration(seconds: 2));
    case 'navigation':
      await harness.unmountChat(tester);
      await harness.mountChat(tester);
    case 'cold_restart':
      // A process-safe cold lifecycle cycle: background/foreground the real
      // device app, then rebuild the production route and rehydrate it.
      requestLiveFault('app_background');
      await Future<void>.delayed(const Duration(seconds: 2));
      requestLiveFault('app_foreground');
      await harness.unmountChat(tester);
      await harness.mountChat(tester);
      await harness.waitOnlineAndLive(tester: tester);
  }}
}}
'''


def _env_int(name: str, default: int) -> int:
    value = os.environ.get(name)
    if value is None:
        return default
    try:
        parsed = int(value)
    except ValueError as error:
        raise ValueError(f"{name} must be an integer") from error
    return parsed


def _capture_rows(path: Path) -> tuple[list[dict[str, Any]], int]:
    rows: list[dict[str, Any]] = []
    malformed = 0
    try:
        with path.open(encoding="utf-8") as stream:
            for line in stream:
                if not line.strip():
                    continue
                try:
                    value = json.loads(line)
                except json.JSONDecodeError:
                    malformed += 1
                    continue
                if isinstance(value, dict) and isinstance(value.get("tag"), str):
                    rows.append(value)
                else:
                    malformed += 1
    except OSError:
        return [], 0
    return rows, malformed


def _has_later_echo(rows: list[dict[str, Any]], message_id: str, sent_index: int) -> bool:
    return any(
        row.get("tag") == "msgEcho"
        and row.get("id") == message_id
        for row in rows[sent_index + 1 :]
    )


def _evaluate_rows(rows: list[dict[str, Any]]) -> dict[str, Any]:
    swallow = False
    for index, row in enumerate(rows):
        if (
            row.get("tag") == "msgSend"
            and row.get("blocked") is True
            and isinstance(row.get("id"), str)
            and not _has_later_echo(rows, row["id"], index)
        ):
            swallow = True
            break
    blank_chat = any(
        row.get("tag") == "route" and row.get("phase") == "projection-empty"
        for row in rows
    )
    lost = [row for row in rows if row.get("tag") == "connChannelLost"]
    missing_causes = [
        row
        for row in lost
        if not isinstance(row.get("cause"), str)
        or not row.get("cause")
        or row.get("cause") == "unknown"
    ]
    working: dict[str, bool] = {}
    for row in rows:
        if row.get("tag") == "workingConv" and isinstance(row.get("room"), str):
            working[row["room"]] = row.get("working") is True
    return {
        "swallow": swallow,
        "blank_chat": blank_chat,
        "lost_count": len(lost),
        "missing_causes": len(missing_causes),
        "working_stuck_rooms": sorted(room for room, active in working.items() if active),
    }


def _run_triage(captures: list[Path]) -> tuple[list[str], list[dict[str, Any]]]:
    outputs: list[str] = []
    evaluations: list[dict[str, Any]] = []
    for capture in captures:
        result = subprocess.run(
            [sys.executable, str(TRIAGE), str(capture)],
            capture_output=True,
            text=True,
            check=False,
        )
        output = result.stdout.strip()
        if result.stderr.strip():
            output += "\n[triage stderr]\n" + result.stderr.strip()
        outputs.append(output)
        rows, malformed = _capture_rows(capture)
        evaluation = _evaluate_rows(rows)
        evaluation.update({"capture": str(capture), "malformed": malformed, "exit": result.returncode})
        evaluations.append(evaluation)
    return outputs, evaluations


def _write_report(
    path: Path,
    *,
    seed: int,
    duration: int,
    schedule: tuple[ScheduleEvent, ...],
    runner_status: int,
    triage_outputs: list[str],
    evaluations: list[dict[str, Any]],
    suspicious: list[str],
    unexpected: list[str],
) -> None:
    lines = [
        "# Live oddities chaos soak report",
        "",
        f"- Seed: `{seed}`",
        f"- Duration: `{duration}s`",
        f"- Runner exit: `{runner_status}`",
        f"- Schedule events: `{len(schedule)}`",
        "",
        "## Expected findings while fixes remain open",
        "",
        "These are not silently accepted. Their presence is reported and linked; "
        "their absence is suspicious and does not count as a green soak.",
        "",
    ]
    for key, tracking_id in KNOWN_FINDINGS.items():
        present = any(evaluation.get(key) for evaluation in evaluations)
        lines.append(f"- `{tracking_id}` ({key}): **{'PRESENT' if present else 'ABSENT'}**")
    lines.extend(["", "## Invariant evaluation", ""])
    if unexpected:
        lines.extend(f"- **UNEXPECTED**: {item}" for item in unexpected)
    else:
        lines.append("- No unexpected invariant violations.")
    if suspicious:
        lines.extend(f"- **SUSPICIOUS**: {item}" for item in suspicious)
    lines.extend(["", "## Connection churn attribution", ""])
    for evaluation in evaluations:
        lines.append(
            f"- `{evaluation['capture']}`: connChannelLost={evaluation['lost_count']}; "
            f"missing/unknown causes={evaluation['missing_causes']}"
        )
    lines.extend(["", "## Schedule", "", "```json", schedule_fingerprint(schedule), "```", ""])
    lines.extend(["## Triage output tail", "", "```text"])
    combined = "\n\n".join(triage_outputs)
    lines.extend(combined.splitlines()[-120:])
    lines.extend(["```", ""])
    path.write_text("\n".join(lines), encoding="utf-8")


def run(args: argparse.Namespace) -> int:
    duration = args.duration if args.duration is not None else _env_int("E2E_LIVE_SOAK_DURATION", DEFAULT_DURATION_SECONDS)
    seed = args.seed if args.seed is not None else _env_int("E2E_LIVE_SOAK_SEED", DEFAULT_SEED)
    schedule = build_schedule(seed, duration)
    if args.dry_run:
        print(json.dumps({"seed": seed, "duration_seconds": duration, "schedule": [e.as_json() for e in schedule]}, indent=2))
        return 0

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    artifact_dir = Path(args.artifacts or ROOT / ".work" / "session-notes" / f"live-soak-{stamp}-{seed}")
    artifact_dir.mkdir(parents=True, exist_ok=True)
    generated = ROOT / "app" / "integration_test" / f".live_soak_{os.getpid()}.dart"
    generated.write_text(_generated_test(schedule, duration + 300), encoding="utf-8")
    runner_status = 2
    try:
        env = os.environ.copy()
        env.update(
            {
                "E2E_LIVE_TEST_FILE": generated.relative_to(ROOT / "app").as_posix(),
                "E2E_LIVE_ARTIFACT_DIR": str(artifact_dir),
                "E2E_LIVE_TIMEOUT_SECONDS": str(duration + 300),
            }
        )
        result = subprocess.run([str(RUNNER), str(generated.relative_to(ROOT / "app"))], env=env, check=False)
        runner_status = result.returncode
    finally:
        generated.unlink(missing_ok=True)

    captures = sorted(artifact_dir.glob("*.jsonl"))
    triage_outputs, evaluations = _run_triage(captures)
    suspicious: list[str] = []
    unexpected: list[str] = []
    if not captures:
        unexpected.append("no debug capture was pulled from the device")
    for key, tracking_id in KNOWN_FINDINGS.items():
        if not any(evaluation.get(key) for evaluation in evaluations):
            suspicious.append(f"expected finding absent: {tracking_id}")
    for evaluation in evaluations:
        if evaluation["missing_causes"]:
            unexpected.append(
                f"{evaluation['capture']} has {evaluation['missing_causes']} connChannelLost event(s) without an attributed cause"
            )
        if evaluation["working_stuck_rooms"]:
            unexpected.append(
                f"{evaluation['capture']} leaves working=true in room(s): {', '.join(evaluation['working_stuck_rooms'])}"
            )
    if runner_status:
        unexpected.append(f"device lane failed with exit {runner_status}")

    report = artifact_dir / "report.md"
    _write_report(
        report,
        seed=seed,
        duration=duration,
        schedule=schedule,
        runner_status=runner_status,
        triage_outputs=triage_outputs,
        evaluations=evaluations,
        suspicious=suspicious,
        unexpected=unexpected,
    )
    print(f"live soak report: {report}")
    print("\n".join(report.read_text(encoding="utf-8").splitlines()[-40:]))
    if unexpected:
        return 1
    if suspicious:
        return 3
    return 0


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--duration", type=int, help="soak duration in seconds (default: 600 or E2E_LIVE_SOAK_DURATION)")
    result.add_argument("--seed", type=int, help="schedule seed (default: E2E_LIVE_SOAK_SEED or 20260821)")
    result.add_argument("--artifacts", type=Path, help="artifact/report directory")
    result.add_argument("--dry-run", action="store_true", help="print the schedule without starting a device lane")
    return result


if __name__ == "__main__":
    raise SystemExit(run(parser().parse_args()))
