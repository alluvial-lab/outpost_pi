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
# The in-process soak deterministically targets the reconnect identity window.
# Process-level blank-chat targeting belongs to run-live.sh's force-stop lane;
# incidental blank-chat evidence is still reported, but absence is not suspicious.
SOAK_EXPECTED_FINDINGS = frozenset({"swallow"})

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
    process-global randomness. Fault holds are always 2--60 seconds. Planned
    action/fault intervals may overlap so a staged turn can remain active while
    a fault is applied; the serialized schedule is therefore a replay key.
    """
    if duration_seconds < MIN_HOLD_SECONDS:
        raise ValueError("duration must be at least 2 seconds")

    rng = random.Random(seed)
    events: list[ScheduleEvent] = []
    cursor = 0
    # Keep the identity-window reproducer and blank-chat monitoring actions in
    # every normal soak. Only the identity window is a deterministic expected
    # finding here; real process-cold blank targeting lives in run-live.sh.
    if duration_seconds >= 34:
        events.extend(
            (
                ScheduleEvent(5, "action", "send"),
                ScheduleEvent(12, "action", "stage_turn"),
                ScheduleEvent(15, "fault", "net_down", 3, "net_fault down", "net_clear"),
                ScheduleEvent(18, "action", "send_identity_window"),
                ScheduleEvent(22, "action", "resolve_turn"),
                ScheduleEvent(28, "action", "navigation"),
            )
        )
        cursor = 34
    while cursor < duration_seconds:
        remaining_before_gap = duration_seconds - cursor
        if remaining_before_gap < MIN_HOLD_SECONDS:
            break
        gap = rng.randint(MIN_HOLD_SECONDS, min(15, remaining_before_gap))
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
import 'dart:convert';

import 'package:app/ui/chat/chat_page.dart';
import 'package:app/ui/chat/states/chat_state.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

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
        final identityBaseline = await _IdentityBaseline.capture(harness);
        await _assertChaosOracle(
          tester,
          harness,
          identityBaseline,
          checkpoint: 'baseline',
        );
        final clock = Stopwatch()..start();
        for (final event in _schedule) {{
          final target = Duration(
            milliseconds: ((event['at_seconds']! as num) * 1000).round(),
          );
          while (clock.elapsed < target) {{
            await tester.pump(const Duration(milliseconds: 100));
          }}
          await _runEvent(tester, harness, identityBaseline, event);
        }}
        await _assertPostSoakQuiescence(
          tester,
          harness,
          identityBaseline,
        );
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
  _IdentityBaseline identityBaseline,
  Map<String, Object?> event,
) async {{
  final kind = event['kind'];
  if (kind == 'fault') {{
    final captureBaseline = (await harness.captureEvents()).length;
    final expectedRoom = harness.connection.activeRoomId;
    final expectedSelection = harness.preferences.selectedRoomRaw;
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
    String? identityPrompt;
    if (clear != null || event['name'] == 'pi_restart') {{
      if (event['name'] == 'net_down') {{
        // Deliberately overlap reconnect and send, then require the same UI +
        // transcript-DB visibility predicate as the skipped regression test.
        identityPrompt =
            'live soak identity-window probe ${{event['at_seconds']}}';
        final reconnecting = harness.connection.connectTo(harness.peer);
        await harness.sync.sendMessage(identityPrompt);
        await reconnecting;
      }} else {{
        await harness.connection.connectTo(harness.peer);
      }}
      await harness.waitOnlineAndLive(tester: tester);
      if (identityPrompt != null &&
          !await harness.submissionIsVisible(tester, identityPrompt)) {{
        // This is a linked known finding, not a silent pass. The post-run
        // oracle consumes the marker and reports the tracking id.
        debugPrintSynchronously('SOAK_KNOWN_FINDING swallow');
      }}
      await _assertRecoveredRoom(
        tester,
        harness,
        captureBaseline: captureBaseline,
        expectedRoom: expectedRoom,
        expectedSelection: expectedSelection,
      );
      await _assertChaosOracle(
        tester,
        harness,
        identityBaseline,
        checkpoint: 'fault-${{event['at_seconds']}}',
      );
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
    case 'stage_turn':
      await harness.host.post('/turn-control/defer-next', <String, Object>{{
        'reply': 'live soak staged reply',
      }});
      await harness.sync.sendMessage('live soak staged prompt');
      await eventually<Map<String, dynamic>>(tester, () async {{
        final value = await harness.host.tryGet('/turn-control');
        return value?['phase'] == 'pending' ? value : null;
      }}, description: 'staged turn active before overlapping fault');
      await harness.waitForSubmissionVisibility(
        tester,
        'live soak staged prompt',
      );
    case 'resolve_turn':
      await harness.host.post(
        '/turn-control/resolve',
        const <String, Object>{{}},
      );
      await eventually<bool>(
        tester,
        () async => find.text('live soak staged reply').evaluate().isNotEmpty
            ? true
            : null,
        description: 'staged turn reply after fault recovery',
      );
    case 'send_identity_window':
      final prompt =
          'live soak identity-window probe ${{event['at_seconds']}}';
      await harness.sync.sendMessage(prompt);
      await harness.waitForSubmissionVisibility(tester, prompt);
    case 'navigation':
      await harness.unmountChat(tester);
      await harness.mountChat(tester);
    case 'cold_restart':
      // Exercise a foreground lifecycle cycle here; process-level cold-open is
      // covered by the force-stop failure lane in run-live.sh.
      requestLiveFault('app_background');
      await Future<void>.delayed(const Duration(seconds: 2));
      requestLiveFault('app_foreground');
      await harness.unmountChat(tester);
      await harness.mountChat(tester);
      await harness.waitOnlineAndLive(tester: tester);
  }}
}}

Future<void> _assertRecoveredRoom(
  WidgetTester tester,
  LiveDeviceHarness harness, {{
  required int captureBaseline,
  required String expectedRoom,
  required String? expectedSelection,
}}) async {{
  expect(harness.connection.activeRoomId, expectedRoom);
  expect(harness.preferences.selectedRoomRaw, expectedSelection);
  final roomEvents = await eventually<List<Map<String, dynamic>>>(
    tester,
    () async {{
      final fresh = (await harness.captureEvents()).skip(captureBaseline);
      final relevant = fresh
          .where(
            (row) =>
                (row['tag'] == 'route' ||
                    row['tag'] == 'connHydrate' ||
                    row['tag'] == 'connStatus') &&
                row['room'] is String,
          )
          .toList(growable: false);
      return relevant.isEmpty ? null : relevant;
    }},
    description: 'capture evidence for recovered active room',
  );
  expect(
    roomEvents.every((row) => row['room'] == expectedRoom),
    isTrue,
    reason: 'fault recovery must not select another room',
  );
}}

final class _IdentityBaseline {{
  const _IdentityBaseline({{
    required this.ownerPk,
    required this.peerEpk,
    required this.pairedAt,
    required this.sendKey,
    required this.receiveKey,
  }});

  final Uint8List ownerPk;
  final String peerEpk;
  final String pairedAt;
  final String sendKey;
  final String receiveKey;

  static Future<_IdentityBaseline> capture(LiveDeviceHarness harness) async {{
    final ownerPk = harness.ownerBridge.currentOwnerPk;
    final persisted = await harness.storage.loadPeer(harness.peer.remoteEpk);
    expect(ownerPk, isNotNull);
    expect(persisted, isNotNull);
    expect(persisted!.channel, isNotNull);
    return _IdentityBaseline(
      ownerPk: Uint8List.fromList(ownerPk!),
      peerEpk: persisted.remoteEpk,
      pairedAt: persisted.pairedAt,
      sendKey: persisted.channel!.sendKey,
      receiveKey: persisted.channel!.receiveKey,
    );
  }}
}}

Future<void> _assertChaosOracle(
  WidgetTester tester,
  LiveDeviceHarness harness,
  _IdentityBaseline baseline, {{
  required String checkpoint,
  bool requireReplayEvidence = false,
}}) async {{
  var rows = await harness.transcriptRows();
  var uiIds = _renderedProjectionIds(tester);
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline) &&
      !listEquals(rows.map((row) => row.id).toList(), uiIds)) {{
    await tester.pump(const Duration(milliseconds: 100));
    rows = await harness.transcriptRows();
    uiIds = _renderedProjectionIds(tester);
  }}

  final persisted = await harness.storage.loadPeer(baseline.peerEpk);
  final ownerPk = harness.ownerBridge.currentOwnerPk;
  final channelStable = persisted?.channel != null &&
      persisted!.channel!.sendKey == baseline.sendKey &&
      persisted.channel!.receiveKey == baseline.receiveKey;
  final ownerStable = ownerPk != null && listEquals(ownerPk, baseline.ownerPk);
  final pairStable = persisted?.remoteEpk == baseline.peerEpk &&
      persisted?.pairedAt == baseline.pairedAt;

  _emitOracle(<String, Object?>{{
    'tag': 'soakOracleCheckpoint',
    'checkpoint': checkpoint,
    'ownerTail': _tail(ownerPk == null ? '' : base64Encode(ownerPk)),
    'peerTail': _tail(persisted?.remoteEpk ?? ''),
    'pairedAtTail': _tail(persisted?.pairedAt ?? ''),
    'channelStable': channelStable,
  }});
  for (final row in rows) {{
    _emitOracle(<String, Object?>{{
      'tag': 'soakOracleDb',
      'checkpoint': checkpoint,
      'id': row.id,
      'seq': row.seq,
      'tsMs': row.ts.millisecondsSinceEpoch,
    }});
  }}
  for (var index = 0; index < uiIds.length; index++) {{
    _emitOracle(<String, Object?>{{
      'tag': 'soakOracleUi',
      'checkpoint': checkpoint,
      'id': uiIds[index],
      'index': index,
    }});
  }}

  final dbIds = rows.map((row) => row.id).toList(growable: false);
  expect(dbIds.toSet().length, dbIds.length,
      reason: 'reconnect replay must not duplicate transcript delivery');
  expect(uiIds, dbIds,
      reason: 'transcript DB rows must match the rendered bubble projection');
  if (rows.isNotEmpty) {{
    expect(find.byKey(ValueKey(rows.last.id)), findsOneWidget,
        reason: 'the newest projected transcript row must render a bubble');
  }}
  for (var index = 1; index < rows.length; index++) {{
    expect(rows[index].seq, greaterThan(rows[index - 1].seq),
        reason: 'transcript projection sequence must increase');
    expect(
      rows[index].ts.millisecondsSinceEpoch,
      greaterThanOrEqualTo(rows[index - 1].ts.millisecondsSinceEpoch),
      reason: 'canonical server timestamp ordering moved backwards',
    );
  }}
  expect(ownerStable, isTrue,
      reason: 'owner identity silently regenerated during a fault');
  expect(pairStable, isTrue,
      reason: 'paired Pi identity silently changed during a fault');
  expect(channelStable, isTrue,
      reason: 'owner-channel keys silently regenerated during a fault');

  final replayEvents = (await harness.captureEvents())
      .where((event) => event['tag'] == 'replayDedup')
      .toList(growable: false);
  final accepted = <String, int>{{}};
  for (final event in replayEvents) {{
    final sessionId = event['sessionId'];
    final eventIdTail = event['eventIdTail'];
    final dropped = event['dropped'];
    expect(sessionId, isA<String>());
    expect(eventIdTail, isA<String>());
    expect(dropped, isA<bool>());
    if (dropped == false) {{
      final key = '$sessionId/$eventIdTail';
      accepted[key] = (accepted[key] ?? 0) + 1;
    }}
  }}
  expect(accepted.values.where((count) => count > 1), isEmpty,
      reason: 'one replay event was accepted more than once');
  if (requireReplayEvidence) {{
    expect(replayEvents, isNotEmpty,
        reason: 'the seeded soak must exercise replayDedup instrumentation');
  }}
}}

List<String> _renderedProjectionIds(WidgetTester tester) {{
  final chat = find.byType(ChatPage);
  if (chat.evaluate().isEmpty) return const <String>[];
  final viewModel = Provider.of<ChatViewModel>(
    tester.element(chat.first),
    listen: false,
  );
  return switch (viewModel.state) {{
    ChatReady(:final messages) =>
      messages.map((message) => message.id).toList(growable: false),
    _ => const <String>[],
  }};
}}

void _emitOracle(Map<String, Object?> row) {{
  debugPrintSynchronously('SOAK_ORACLE ${{jsonEncode(row)}}');
}}

String _tail(String value) =>
    value.length <= 12 ? value : value.substring(value.length - 12);

Future<void> _assertPostSoakQuiescence(
  WidgetTester tester,
  LiveDeviceHarness harness,
  _IdentityBaseline identityBaseline,
) async {{
  await harness.waitOnlineAndLive(tester: tester);
  final room = harness.connection.activeRoomId;
  await eventually<bool>(
    tester,
    () async =>
        harness.connection.isRoomWorking(harness.peer.remoteEpk, room)
            ? null
            : true,
    description: 'post-soak working=false after quiesce',
  );
  expect(
    harness.connection.isRoomWorking(harness.peer.remoteEpk, room),
    isFalse,
  );
  await _assertChaosOracle(
    tester,
    harness,
    identityBaseline,
    checkpoint: 'final',
    requireReplayEvidence: true,
  );
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


def _blank_chat_signature(rows: list[dict[str, Any]]) -> bool:
    for index, row in enumerate(rows):
        if row.get("tag") != "route" or row.get("phase") != "projection-empty":
            continue
        room = row.get("room")
        session = row.get("sessionIdTail")

        def same_projection(candidate: dict[str, Any]) -> bool:
            candidate_session = candidate.get("sessionIdTail")
            return candidate.get("room") == room and not (
                isinstance(session, str)
                and isinstance(candidate_session, str)
                and session != candidate_session
            )

        history_existed = any(
            same_projection(candidate)
            and (
                (
                    candidate.get("tag") == "route"
                    and candidate.get("phase") == "projection-ready"
                    and isinstance(candidate.get("messageCount"), int)
                    and candidate["messageCount"] > 0
                )
                or (
                    candidate.get("tag") == "sessionSync"
                    and isinstance(candidate.get("messageCount"), int)
                    and candidate["messageCount"] > 0
                )
            )
            for candidate in rows[:index]
        )
        rendered_later = any(
            same_projection(candidate)
            and candidate.get("tag") == "route"
            and candidate.get("phase") == "projection-ready"
            and isinstance(candidate.get("messageCount"), int)
            and candidate["messageCount"] > 0
            for candidate in rows[index + 1 :]
        )
        if history_existed and not rendered_later:
            return True
    return False


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
    blank_chat = _blank_chat_signature(rows)
    lost = [row for row in rows if row.get("tag") == "connChannelLost"]
    missing_causes = [
        row
        for row in lost
        if not isinstance(row.get("cause"), str)
        or not row.get("cause")
        or row.get("cause") == "unknown"
    ]
    return {
        "swallow": swallow,
        "blank_chat": blank_chat,
        "lost_count": len(lost),
        "missing_causes": len(missing_causes),
    }


def _oracle_rows_from_flutter(output: str) -> tuple[list[dict[str, Any]], int]:
    rows: list[dict[str, Any]] = []
    malformed = 0
    marker = "SOAK_ORACLE "
    for line in output.splitlines():
        if marker not in line:
            continue
        encoded = line.split(marker, 1)[1].strip()
        try:
            value = json.loads(encoded)
        except json.JSONDecodeError:
            malformed += 1
            continue
        if isinstance(value, dict) and isinstance(value.get("tag"), str):
            rows.append(value)
        else:
            malformed += 1
    return rows, malformed


def _run_triage(
    captures: list[Path],
    oracle_path: Path | None = None,
) -> tuple[list[str], list[dict[str, Any]]]:
    outputs: list[str] = []
    evaluations: list[dict[str, Any]] = []
    for capture in captures:
        command = [sys.executable, str(TRIAGE), str(capture)]
        if oracle_path is not None:
            command.extend(("--oracle", str(oracle_path)))
        result = subprocess.run(
            command,
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
        "## Known findings while fixes remain open",
        "",
        "These are not silently accepted. Presence is reported and linked; absence "
        "is suspicious only for findings deterministically targeted by this schedule.",
        "",
    ]
    for key, tracking_id in KNOWN_FINDINGS.items():
        present = any(evaluation.get(key) for evaluation in evaluations)
        expectation = "targeted" if key in SOAK_EXPECTED_FINDINGS else "incidental"
        lines.append(
            f"- `{tracking_id}` ({key}, {expectation}): "
            f"**{'PRESENT' if present else 'ABSENT'}**"
        )
    lines.extend(
        [
            "",
            "## Invariant evaluation",
            "",
            "- Replay dedup: replayDedup acceptance keys and transcript ids stay unique across reconnect replay.",
            "- DB↔UI consistency: ordered transcript DB ids equal the rendered ChatReady bubble projection after every fault.",
            "- Canonical ordering: projected row timestamps never move backwards; sequence is the stable tie order.",
            "- Identity stability: owner public key, paired Pi identity, pairing epoch, and owner-channel keys stay stable.",
        ]
    )
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

    captures = sorted(artifact_dir.glob("outpost_pi_debug-*.jsonl"))
    flutter_output = "\n".join(
        path.read_text(encoding="utf-8", errors="replace")
        for path in sorted(artifact_dir.glob("flutter-live-*.log"))
    )
    oracle_rows, malformed_oracle = _oracle_rows_from_flutter(flutter_output)
    oracle_path: Path | None = None
    if oracle_rows:
        oracle_path = artifact_dir / "soak-oracle.jsonl"
        oracle_path.write_text(
            "".join(json.dumps(row, sort_keys=True) + "\n" for row in oracle_rows),
            encoding="utf-8",
        )
    triage_outputs, evaluations = _run_triage(captures, oracle_path)
    if "SOAK_KNOWN_FINDING swallow" in flutter_output and evaluations:
        evaluations[0]["swallow"] = True
        evaluations[0]["swallow_source"] = "bubble/transcript-DB predicate"
    suspicious: list[str] = []
    unexpected: list[str] = []
    if not captures:
        unexpected.append("no debug capture was pulled from the device")
    if not oracle_rows:
        unexpected.append("no content-free soak oracle observations were captured")
    if malformed_oracle:
        unexpected.append(f"{malformed_oracle} malformed soak oracle observation(s)")
    for output in triage_outputs:
        for invariant in ("replay_dedup", "transcript_ui", "ordering", "identity"):
            if f"  {invariant}: VIOLATION" in output:
                unexpected.append(f"triage detected {invariant} invariant violation")
    for key in SOAK_EXPECTED_FINDINGS:
        tracking_id = KNOWN_FINDINGS[key]
        if not any(evaluation.get(key) for evaluation in evaluations):
            suspicious.append(f"expected finding absent: {tracking_id}")
    for evaluation in evaluations:
        if evaluation["missing_causes"]:
            unexpected.append(
                f"{evaluation['capture']} has {evaluation['missing_causes']} connChannelLost event(s) without an attributed cause"
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
