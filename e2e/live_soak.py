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
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable

ROOT = Path(__file__).resolve().parent.parent
RUNNER = ROOT / "e2e" / "run-live.sh"
TRIAGE = ROOT / "scripts" / "debug_capture_triage.py"
DEFAULT_DURATION_SECONDS = 10 * 60
DEFAULT_SEED = 20260821
MIN_HOLD_SECONDS = 2
MAX_HOLD_SECONDS = 60

KNOWN_FINDINGS_MANIFEST = ROOT / "e2e" / "expected-soak-findings.txt"


def _load_known_findings(path: Path = KNOWN_FINDINGS_MANIFEST) -> tuple[str, ...]:
    """Load the canonical known-open inventory in manifest order."""
    return tuple(
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    )


KNOWN_FINDINGS = _load_known_findings()


def _known_finding(fragment: str) -> str:
    matches = [tracking_id for tracking_id in KNOWN_FINDINGS if fragment in tracking_id]
    if len(matches) != 1:
        raise RuntimeError(f"known-finding fragment {fragment!r} matched {len(matches)} ids")
    return matches[0]


FINDING_OBSERVATIONS = {
    "blank_chat": _known_finding("blank-chat-direct-open"),
    "reconnect_churn": _known_finding("reconnect-churn-timeout"),
    "cold_dedup": _known_finding("cold-replay-duplicates"),
    "mesh_roster": _known_finding("mesh-post-pair-roster"),
    "session_rotation_working": _known_finding("session-rotation-late-echo"),
}
# Blank-chat targeting belongs to run-live.sh's force-stop lane, while cold
# replay and mesh-roster findings belong to the grid and two-Pi lanes. Long
# soaks also carry the state-shape linked skip until its working bug is fixed.
SOAK_EXPECTED_FINDINGS: frozenset[str] = frozenset()
# The real multi-session exercise always runs in a full soak, but the linked
# late-echo defect is timing-dependent; mark it only when the exercise observes it.
SOAK_LONG_EXPECTED_FINDINGS: frozenset[str] = frozenset()
SOAK_OUT_OF_LANE_FINDINGS = frozenset(
    {"reconnect_churn", "cold_dedup", "mesh_roster"}
)
CHURN_CLUSTER_SECONDS = 60
CHURN_RECOVERY_SECONDS = 60

NET_FAULT_WEIGHTS = (
    ("timeout", 10),
    ("slicer", 8),
    ("down", 8),
    ("latency", 14),
    ("bandwidth", 12),
    ("slow_close", 10),
)
COMPOUND_CLASSES = ("timeout", "slicer", "latency", "bandwidth", "slow_close")
FAULT_WEIGHTS = (
    ("net_fault", 28),
    ("net_compound", 10),
    ("relay_pause", 8),
    ("relay_kill", 8),
    ("pi_restart", 10),
    ("app_background", 8),
    ("app_airplane", 8),
)
ACTION_WEIGHTS = (("send", 20), ("navigation", 9), ("cold_restart", 5))
VOCABULARY_PROBE_DURATION_SECONDS = 90
STATE_SHAPE_PROBE_DURATION_SECONDS = 300
REQUIRED_FAULT_DEMOS = (
    ("latency", "net_fault latency"),
    ("bandwidth", "net_fault bandwidth"),
    ("slow_close", "net_fault slow_close"),
    ("compound", "net_compound "),
    ("relay_kill", "relay_kill"),
)


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


def _fault_value(rng: random.Random, fault_class: str) -> int:
    if fault_class == "latency":
        return rng.randint(100, 1_200)
    if fault_class == "bandwidth":
        return rng.randint(16, 256)
    if fault_class == "slow_close":
        return rng.randint(250, 4_000)
    return rng.randint(500, 8_000)


def _fault_event(rng: random.Random, at: int, remaining: int) -> ScheduleEvent:
    name = _weighted_choice(rng, FAULT_WEIGHTS)
    hold = rng.randint(MIN_HOLD_SECONDS, min(MAX_HOLD_SECONDS, remaining))
    if name == "net_fault":
        fault_class = _weighted_choice(rng, NET_FAULT_WEIGHTS)
        command = f"net_fault {fault_class}"
        if fault_class != "down":
            command += f" {_fault_value(rng, fault_class)}"
        return ScheduleEvent(
            at_seconds=at,
            kind="fault",
            name=f"net_{fault_class}",
            hold_seconds=hold,
            command=command,
            clear_command="net_clear",
        )
    if name == "net_compound":
        classes = rng.sample(COMPOUND_CLASSES, k=rng.randint(2, 3))
        specifications = " ".join(
            f"{fault_class}={_fault_value(rng, fault_class)}"
            for fault_class in classes
        )
        return ScheduleEvent(
            at,
            "fault",
            name,
            hold,
            f"net_compound {specifications}",
            "net_clear",
        )
    if name == "relay_pause":
        return ScheduleEvent(at, "fault", name, hold, "relay_pause", "relay_resume")
    if name == "relay_kill":
        return ScheduleEvent(at, "fault", name, hold, "relay_kill", None)
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
    if duration_seconds >= VOCABULARY_PROBE_DURATION_SECONDS:
        events.extend(
            (
                ScheduleEvent(
                    36, "fault", "net_latency", 3, "net_fault latency 250", "net_clear"
                ),
                ScheduleEvent(
                    43, "fault", "net_bandwidth", 3, "net_fault bandwidth 64", "net_clear"
                ),
                ScheduleEvent(
                    50,
                    "fault",
                    "net_slow_close",
                    3,
                    "net_fault slow_close 750",
                    "net_clear",
                ),
                ScheduleEvent(
                    57,
                    "fault",
                    "net_compound",
                    3,
                    "net_compound latency=200 bandwidth=64",
                    "net_clear",
                ),
                ScheduleEvent(64, "fault", "relay_kill", 8, "relay_kill", None),
                ScheduleEvent(76, "action", "navigation"),
            )
        )
        cursor = 80
    if duration_seconds >= STATE_SHAPE_PROBE_DURATION_SECONDS:
        events.extend(
            (
                ScheduleEvent(84, "state_shape", "multi_session_round_trip"),
                ScheduleEvent(150, "state_shape", "long_uptime_replay"),
            )
        )
        cursor = 170
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

import 'package:app/data/preferences/preferences.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/ui/chat/chat_page.dart';
import 'package:app/ui/chat/states/chat_state.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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
        ((event['name']! as String).startsWith('net_') ||
            event['name'] == 'relay_pause')) {{
      await harness.connection.disconnect();
    }}
    if (clear is String) requestLiveFault(clear);
    String? identityPrompt;
    if (clear != null ||
        event['name'] == 'pi_restart' ||
        event['name'] == 'relay_kill') {{
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
        fail('identity-window submission disappeared after reconnect');
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
    case 'multi_session_round_trip':
      debugPrintSynchronously(
        'SOAK_STATE_SHAPE multi_session_round_trip started',
      );
      final result = await harness.exerciseMultiSessionShape(
        tester,
        assertWorkingConverged: false,
      );
      if (!result.workingConverged) {{
        // The marker records the linked late-echo defect only after the real
        // A→B→A product exercise reaches its working-state observation.
        debugPrintSynchronously(
          'SOAK_KNOWN_FINDING session_rotation_working',
        );
      }}
      debugPrintSynchronously(
        'SOAK_STATE_SHAPE multi_session_round_trip exercised',
      );
    case 'long_uptime_replay':
      await harness.exerciseLongUptimeShape(
        tester,
        ringEvents: 200,
        requireRotation: false,
      );
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
  var projectionIds = _viewModelProjectionIds(tester);
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline) &&
      !listEquals(rows.map((row) => row.id).toList(), projectionIds)) {{
    await tester.pump(const Duration(milliseconds: 100));
    rows = await harness.transcriptRows();
    projectionIds = _viewModelProjectionIds(tester);
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
  for (var index = 0; index < projectionIds.length; index++) {{
    _emitOracle(<String, Object?>{{
      'tag': 'soakOracleProjection',
      'checkpoint': checkpoint,
      'id': projectionIds[index],
      'index': index,
    }});
  }}

  final dbIds = rows.map((row) => row.id).toList(growable: false);
  expect(dbIds.toSet().length, dbIds.length,
      reason: 'reconnect replay must not duplicate transcript delivery');
  expect(projectionIds, dbIds,
      reason: 'transcript DB rows must match the ChatReady ViewModel projection');
  await _assertEveryMaintainedBubbleRenders(
    tester,
    await _waitForRenderableProjection(tester),
  );
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

List<String> _viewModelProjectionIds(WidgetTester tester) {{
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

List<String> _renderableProjectionIds(WidgetTester tester) {{
  final chat = find.byType(ChatPage);
  if (chat.evaluate().isEmpty) return const <String>[];
  final element = tester.element(chat.first);
  final viewModel = Provider.of<ChatViewModel>(element, listen: false);
  final hideToolCalls = Provider.of<Preferences>(element, listen: false).hideToolCalls;
  return switch (viewModel.state) {{
    ChatReady(:final messages) => messages
        .where((message) => !hideToolCalls || message is! ToolEvent)
        .map((message) => message.id)
        .toList(growable: false),
    _ => const <String>[],
  }};
}}

Future<List<String>> _waitForRenderableProjection(WidgetTester tester) async {{
  var ids = _renderableProjectionIds(tester);
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (ids.isNotEmpty &&
      find.byType(ListView).evaluate().isEmpty &&
      DateTime.now().isBefore(deadline)) {{
    await tester.pump(const Duration(milliseconds: 100));
    ids = _renderableProjectionIds(tester);
  }}
  return ids;
}}

Future<void> _assertEveryMaintainedBubbleRenders(
  WidgetTester tester,
  List<String> expectedIds,
) async {{
  if (expectedIds.isEmpty) return;
  final list = find.byType(ListView);
  expect(list, findsOneWidget);
  final scrollable = find
      .descendant(
        of: list,
        matching: find.byType(Scrollable),
      )
      .first;
  expect(scrollable, findsOneWidget);
  final expectedNewestFirst = expectedIds.reversed.toList(growable: false);
  final rendered = <String>{{}};
  for (final id in expectedNewestFirst) {{
    final bubble = find.byKey(ValueKey<String>(id));
    await tester.scrollUntilVisible(
      bubble,
      240,
      scrollable: scrollable,
      maxScrolls: expectedIds.length * 4 + 4,
    );
    expect(bubble, findsOneWidget,
        reason: 'every maintained transcript id must render as a bubble');
    rendered.add(id);
    final materialized = find
        .descendant(
          of: list,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is KeyedSubtree &&
                widget.key is ValueKey<String> &&
                expectedIds.contains((widget.key! as ValueKey<String>).value),
          ),
        )
        .evaluate()
        .map((element) => (element.widget.key! as ValueKey<String>).value)
        .toList(growable: false);
    expect(
      materialized,
      expectedNewestFirst.where(materialized.contains).toList(growable: false),
      reason: 'materialized bubble widgets must retain newest-to-oldest list order',
    );
  }}
  expect(rendered, expectedIds.toSet(),
      reason: 'widget traversal must materialize every maintained bubble id');
  await tester.scrollUntilVisible(
    find.byKey(ValueKey<String>(expectedIds.last)),
    -240,
    scrollable: scrollable,
    maxScrolls: expectedIds.length * 4 + 4,
  );
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


def _parse_timestamp(value: Any) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo is not None else parsed.replace(tzinfo=timezone.utc)


def _load_fault_windows(path: Path) -> tuple[tuple[datetime, datetime], ...]:
    """Load host-recorded scheduled fault windows, including recovery time."""
    events, _ = _capture_rows(path)
    active: list[datetime] = []
    windows: list[tuple[datetime, datetime]] = []
    for event in events:
        timestamp = _parse_timestamp(event.get("ts"))
        phase = event.get("phase")
        if timestamp is None:
            continue
        if phase == "start":
            active.append(timestamp)
        elif phase == "end":
            for started in active:
                windows.append(
                    (
                        started - timedelta(seconds=2),
                        timestamp + timedelta(seconds=CHURN_RECOVERY_SECONDS),
                    )
                )
            active.clear()
    for started in active:
        windows.append(
            (
                started - timedelta(seconds=2),
                started + timedelta(seconds=CHURN_RECOVERY_SECONDS),
            )
        )
    return tuple(windows)


def _churn_clusters(
    rows: list[dict[str, Any]],
) -> list[list[dict[str, Any]]]:
    losses = sorted(
        (
            row
            for row in rows
            if row.get("tag") == "connChannelLost"
            and _parse_timestamp(row.get("ts")) is not None
        ),
        key=lambda row: _parse_timestamp(row.get("ts")) or datetime.max.replace(tzinfo=timezone.utc),
    )
    clusters: list[list[dict[str, Any]]] = []
    for row in losses:
        timestamp = _parse_timestamp(row.get("ts"))
        if not clusters:
            clusters.append([row])
            continue
        previous = _parse_timestamp(clusters[-1][-1].get("ts"))
        if previous is not None and timestamp is not None and (
            timestamp - previous
        ).total_seconds() <= CHURN_CLUSTER_SECONDS:
            clusters[-1].append(row)
        else:
            clusters.append([row])
    return [cluster for cluster in clusters if len(cluster) >= 2]


def _reconcile_churn(
    rows: list[dict[str, Any]],
    fault_windows: tuple[tuple[datetime, datetime], ...],
) -> tuple[int, int]:
    """Partition anomalous churn clusters by scheduled fault/recovery windows."""
    expected = 0
    unexpected = 0
    for cluster in _churn_clusters(rows):
        timestamps = [
            timestamp
            for row in cluster
            if (timestamp := _parse_timestamp(row.get("ts"))) is not None
        ]
        if timestamps and all(
            any(start <= timestamp <= end for start, end in fault_windows)
            for timestamp in timestamps
        ):
            expected += 1
        else:
            unexpected += 1
    return expected, unexpected


def _has_later_echo(rows: list[dict[str, Any]], message_id: str, sent_index: int) -> bool:
    return any(
        row.get("tag") == "msgEcho"
        and row.get("id") == message_id
        for row in rows[sent_index + 1 :]
    )


def _has_later_visible_send_state(
    rows: list[dict[str, Any]], message_id: str, sent_index: int
) -> bool:
    return any(
        row.get("tag") == "sendQueue"
        and row.get("id") == message_id
        and row.get("phase") in {"held", "visible-fail"}
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


def _evaluate_rows(
    rows: list[dict[str, Any]],
    fault_windows: tuple[tuple[datetime, datetime], ...] = (),
) -> dict[str, Any]:
    swallow = False
    for index, row in enumerate(rows):
        if (
            row.get("tag") == "msgSend"
            and row.get("blocked") is True
            and isinstance(row.get("id"), str)
            and not _has_later_echo(rows, row["id"], index)
            and not _has_later_visible_send_state(rows, row["id"], index)
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
    expected_churn, unexpected_churn = _reconcile_churn(rows, fault_windows)
    return {
        "swallow": swallow,
        "blank_chat": blank_chat,
        "reconnect_churn": unexpected_churn > 0,
        "lost_count": len(lost),
        "missing_causes": len(missing_causes),
        "expected_churn_clusters": expected_churn,
        "unexpected_churn_clusters": unexpected_churn,
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


def _fault_demonstrations(output: str) -> tuple[list[str], list[str]]:
    commands = [
        line.split("[live] applied ", 1)[1].strip()
        for line in output.splitlines()
        if "[live] applied " in line
    ]
    demonstrated = [
        label
        for label, prefix in REQUIRED_FAULT_DEMOS
        if any(command.startswith(prefix) for command in commands)
    ]
    missing = [label for label, _ in REQUIRED_FAULT_DEMOS if label not in demonstrated]
    return demonstrated, missing


def _run_triage(
    captures: list[Path],
    oracle_path: Path | None = None,
    fault_windows: tuple[tuple[datetime, datetime], ...] = (),
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
        evaluation = _evaluate_rows(rows, fault_windows)
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
    demonstrated_faults: list[str],
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
        "## Expected known-open findings",
        "",
        "Every currently open finding remains present in the nightly inventory and "
        "is linked below. Observation is separate: only findings exercised by this "
        "single-Pi, in-process schedule are expected to reproduce in this report.",
        "",
    ]
    for key, tracking_id in FINDING_OBSERVATIONS.items():
        observed = any(evaluation.get(key) for evaluation in evaluations)
        expectation = (
            "targeted"
            if key in SOAK_EXPECTED_FINDINGS
            or (
                duration >= STATE_SHAPE_PROBE_DURATION_SECONDS
                and key in SOAK_LONG_EXPECTED_FINDINGS
            )
            else "out-of-lane"
            if key in SOAK_OUT_OF_LANE_FINDINGS
            else "incidental"
        )
        lines.append(
            f"- `{tracking_id}` ({key}, {expectation}): **PRESENT**; "
            f"soak observation **{'OBSERVED' if observed else 'NOT OBSERVED'}**"
        )
    lines.extend(
        [
            "",
            "## Invariant evaluation",
            "",
            "- Replay dedup: replayDedup acceptance keys and transcript ids stay unique across reconnect replay.",
            "- DB↔ViewModel projection: ordered transcript DB ids equal the ChatReady message projection after every fault.",
            "- Rendered bubbles: widget traversal materializes every maintained message id and preserves order in each visible window.",
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
    lines.extend(["", "## Fault vocabulary evidence", ""])
    for label, _ in REQUIRED_FAULT_DEMOS:
        lines.append(
            f"- `{label}`: "
            f"**{'APPLIED' if label in demonstrated_faults else 'NOT OBSERVED'}**"
        )
    lines.extend(["", "## Connection churn attribution", ""])
    for evaluation in evaluations:
        lines.append(
            f"- `{evaluation['capture']}`: connChannelLost={evaluation['lost_count']}; "
            f"expected scheduled-fault clusters={evaluation['expected_churn_clusters']}; "
            f"outside-window clusters={evaluation['unexpected_churn_clusters']}; "
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
    artifact_dir = Path(
        args.artifacts
        or ROOT / ".work" / "session-notes" / f"live-soak-{stamp}-{seed}"
    ).resolve()
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
    fault_output = "\n".join(
        path.read_text(encoding="utf-8", errors="replace")
        for path in sorted(artifact_dir.glob("faults-applied.log"))
    )
    demonstrated_faults, missing_faults = _fault_demonstrations(fault_output)
    oracle_path: Path | None = None
    if oracle_rows:
        oracle_path = artifact_dir / "soak-oracle.jsonl"
        oracle_path.write_text(
            "".join(json.dumps(row, sort_keys=True) + "\n" for row in oracle_rows),
            encoding="utf-8",
        )
    fault_windows = _load_fault_windows(artifact_dir / "fault-windows.jsonl")
    triage_outputs, evaluations = _run_triage(
        captures,
        oracle_path,
        fault_windows,
    )
    if "SOAK_KNOWN_FINDING session_rotation_working" in flutter_output and evaluations:
        evaluations[0]["session_rotation_working"] = True
        evaluations[0]["session_rotation_working_source"] = "real multi-session exercise"
    suspicious: list[str] = []
    unexpected: list[str] = []
    if not captures:
        unexpected.append("no debug capture was pulled from the device")
    if not oracle_rows:
        unexpected.append("no content-free soak oracle observations were captured")
    if malformed_oracle:
        unexpected.append(f"{malformed_oracle} malformed soak oracle observation(s)")
    if duration >= VOCABULARY_PROBE_DURATION_SECONDS and missing_faults:
        unexpected.append(
            "scheduled fault demonstrations were not applied: " + ", ".join(missing_faults)
        )
    if duration >= STATE_SHAPE_PROBE_DURATION_SECONDS and (
        "SOAK_STATE_SHAPE multi_session_round_trip exercised" not in flutter_output
    ):
        unexpected.append("scheduled real multi-session exercise did not complete")
    for output in triage_outputs:
        for invariant in ("replay_dedup", "transcript_projection", "ordering", "identity"):
            if f"  {invariant}: VIOLATION" in output:
                unexpected.append(f"triage detected {invariant} invariant violation")
    expected_findings = set(SOAK_EXPECTED_FINDINGS)
    if duration >= STATE_SHAPE_PROBE_DURATION_SECONDS:
        expected_findings.update(SOAK_LONG_EXPECTED_FINDINGS)
    for key in expected_findings:
        tracking_id = FINDING_OBSERVATIONS[key]
        if not any(evaluation.get(key) for evaluation in evaluations):
            suspicious.append(f"expected finding absent: {tracking_id}")
    for evaluation in evaluations:
        if evaluation["missing_causes"]:
            unexpected.append(
                f"{evaluation['capture']} has {evaluation['missing_causes']} connChannelLost event(s) without an attributed cause"
            )
        if evaluation["unexpected_churn_clusters"]:
            unexpected.append(
                f"{evaluation['capture']} has {evaluation['unexpected_churn_clusters']} churn cluster(s) outside every scheduled fault window"
            )
        if evaluation["exit"] > 1:
            unexpected.append(
                f"triage failed for {evaluation['capture']} with exit {evaluation['exit']}"
            )
        elif evaluation["exit"] == 1 and not (
            (evaluation["swallow"] and "swallow" in FINDING_OBSERVATIONS)
            or (
                evaluation["blank_chat"]
                and "blank_chat" in FINDING_OBSERVATIONS
            )
            or evaluation["expected_churn_clusters"]
            or evaluation["unexpected_churn_clusters"]
        ):
            unexpected.append(
                f"triage reported an unreconciled anomaly for {evaluation['capture']}"
            )
    reconciled_outputs: list[str] = []
    for output, evaluation in zip(triage_outputs, evaluations, strict=True):
        oracle_violation = any(
            f"  {name}: VIOLATION" in output
            for name in ("replay_dedup", "transcript_projection", "ordering", "identity")
        )
        reconciled = (
            evaluation["exit"] == 1
            and not oracle_violation
            and not evaluation["unexpected_churn_clusters"]
            and (
                (
                    evaluation["swallow"]
                    and "swallow" in FINDING_OBSERVATIONS
                )
                or (
                    evaluation["blank_chat"]
                    and "blank_chat" in FINDING_OBSERVATIONS
                )
                or evaluation["expected_churn_clusters"]
            )
        )
        if reconciled:
            output = output.replace(
                "Anomalies: FOUND",
                "Anomalies: RECONCILED (known-open or scheduled-fault churn)",
            )
        reconciled_outputs.append(output)
    triage_outputs = reconciled_outputs
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
        demonstrated_faults=demonstrated_faults,
        suspicious=suspicious,
        unexpected=unexpected,
    )
    observed_findings = sorted(
        tracking_id
        for key, tracking_id in FINDING_OBSERVATIONS.items()
        if any(evaluation.get(key) for evaluation in evaluations)
    )
    (artifact_dir / "findings.json").write_text(
        json.dumps(
            {
                "known_open": sorted(KNOWN_FINDINGS),
                "observed": observed_findings,
                "suspicious": suspicious,
                "unexpected": unexpected,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
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
