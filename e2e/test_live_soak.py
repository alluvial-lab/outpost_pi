import importlib.util
import sys
import unittest
from pathlib import Path


_SPEC = importlib.util.spec_from_file_location("live_soak", Path(__file__).with_name("live_soak.py"))
assert _SPEC and _SPEC.loader
live_soak = importlib.util.module_from_spec(_SPEC)
sys.modules["live_soak"] = live_soak
_SPEC.loader.exec_module(live_soak)

_TRIAGE_SPEC = importlib.util.spec_from_file_location(
    "debug_capture_triage",
    Path(__file__).parents[1] / "scripts" / "debug_capture_triage.py",
)
assert _TRIAGE_SPEC and _TRIAGE_SPEC.loader
triage = importlib.util.module_from_spec(_TRIAGE_SPEC)
sys.modules["debug_capture_triage"] = triage
_TRIAGE_SPEC.loader.exec_module(triage)


class ScheduleTests(unittest.TestCase):
    def test_same_seed_produces_same_schedule(self) -> None:
        first = live_soak.build_schedule(1234, 600)
        second = live_soak.build_schedule(1234, 600)
        self.assertEqual(first, second)
        self.assertEqual(
            live_soak.schedule_fingerprint(first),
            live_soak.schedule_fingerprint(second),
        )

    def test_different_seed_changes_schedule(self) -> None:
        self.assertNotEqual(
            live_soak.build_schedule(1234, 600),
            live_soak.build_schedule(1235, 600),
        )

    def test_fault_holds_are_bounded_and_a_fault_overlaps_a_staged_turn(self) -> None:
        schedule = live_soak.build_schedule(42, 600)
        for event in schedule:
            if event.kind == "fault":
                self.assertGreaterEqual(event.hold_seconds, live_soak.MIN_HOLD_SECONDS)
                self.assertLessEqual(event.hold_seconds, live_soak.MAX_HOLD_SECONDS)
        self.assertTrue(all(event.at_seconds < 600 for event in schedule))

        staged = next(event for event in schedule if event.name == "stage_turn")
        resolved = next(event for event in schedule if event.name == "resolve_turn")
        overlapping_faults = [
            event
            for event in schedule
            if event.kind == "fault"
            and staged.at_seconds < event.at_seconds < resolved.at_seconds
        ]
        self.assertTrue(overlapping_faults)

    def test_short_duration_boundary_never_uses_an_empty_randint_range(self) -> None:
        for duration in (2, 3, 33, 34, 35, 89, 90, 91):
            schedule = live_soak.build_schedule(7, duration)
            self.assertTrue(all(event.at_seconds < duration for event in schedule))

    def test_short_seeded_soak_schedules_every_new_fault_demonstration(self) -> None:
        schedule = live_soak.build_schedule(20260822, 180)
        commands = [event.command or "" for event in schedule]
        expected = {
            "net_fault latency 250",
            "net_fault bandwidth 64",
            "net_fault slow_close 750",
            "net_compound latency=200 bandwidth=64",
            "relay_kill",
        }
        self.assertTrue(expected.issubset(commands))

    def test_full_soak_schedules_bounded_state_shapes(self) -> None:
        short = live_soak.build_schedule(20260822, 299)
        full = live_soak.build_schedule(20260822, 300)
        self.assertFalse(any(event.kind == "state_shape" for event in short))
        self.assertEqual(
            [event.name for event in full if event.kind == "state_shape"],
            ["multi_session_round_trip", "long_uptime_replay"],
        )

    def test_random_scheduler_can_pick_new_classes_and_compounds(self) -> None:
        events = [
            live_soak._fault_event(live_soak.random.Random(seed), 10, 100)
            for seed in range(500)
        ]
        names = {event.name for event in events}
        expected = {
            "net_latency",
            "net_bandwidth",
            "net_slow_close",
            "net_compound",
            "relay_kill",
        }
        self.assertTrue(expected.issubset(names))
        for event in events:
            if event.name == "net_compound":
                specifications = event.command.split()[1:]
                self.assertIn(len(specifications), (2, 3))
                self.assertEqual(
                    len(specifications),
                    len({spec.split("=", 1)[0] for spec in specifications}),
                )

    def test_applied_fault_log_requires_each_demonstration(self) -> None:
        output = "\n".join(
            f"[live] applied {command}"
            for command in (
                "net_fault latency 250",
                "net_fault bandwidth 64",
                "net_fault slow_close 750",
                "net_compound latency=200 bandwidth=64",
                "relay_kill",
            )
        )
        demonstrated, missing = live_soak._fault_demonstrations(output)
        self.assertEqual(
            set(demonstrated),
            {label for label, _ in live_soak.REQUIRED_FAULT_DEMOS},
        )
        self.assertEqual(missing, [])

    def test_generated_device_oracle_covers_all_four_invariants(self) -> None:
        source = live_soak._generated_test(live_soak.build_schedule(7, 60), 360)
        for evidence in (
            "replayDedup",
            "transcript DB rows must match the rendered bubble projection",
            "canonical server timestamp ordering moved backwards",
            "owner identity silently regenerated during a fault",
            "event['name'] == 'relay_kill'",
            "harness.exerciseMultiSessionShape(tester)",
            "harness.exerciseLongUptimeShape(",
        ):
            self.assertIn(evidence, source)

    def test_oracle_markers_are_parsed_without_flutter_prefixes(self) -> None:
        rows, malformed = live_soak._oracle_rows_from_flutter(
            'flutter: SOAK_ORACLE {"tag":"soakOracleCheckpoint","checkpoint":"final"}\n'
            "flutter: SOAK_ORACLE not-json\n"
        )
        self.assertEqual(len(rows), 1)
        self.assertEqual(malformed, 1)


class OracleLogicTests(unittest.TestCase):
    def test_clean_replay_db_ui_ordering_and_identity_observations(self) -> None:
        capture = (
            {
                "tag": "replayDedup",
                "sessionId": "session-a",
                "eventIdTail": "event-a",
                "dropped": False,
            },
            {
                "tag": "replayDedup",
                "sessionId": "session-a",
                "eventIdTail": "event-a",
                "dropped": True,
            },
        )
        oracle = self._checkpoint("baseline", ("a", "b"), (100, 101))
        result = triage._chaos_oracle_violations(capture, oracle)
        self.assertFalse(any(result.values()))

    def test_each_oracle_invariant_reports_its_own_violation(self) -> None:
        accepted_twice = (
            {
                "tag": "replayDedup",
                "sessionId": "session-a",
                "eventIdTail": "event-a",
                "dropped": False,
            },
            {
                "tag": "replayDedup",
                "sessionId": "session-a",
                "eventIdTail": "event-a",
                "dropped": False,
            },
        )
        oracle = list(self._checkpoint("baseline", ("a", "a"), (101, 100)))
        oracle.append(
            {
                "tag": "soakOracleCheckpoint",
                "checkpoint": "fault-1",
                "ownerTail": "owner-b",
                "peerTail": "peer-a",
                "pairedAtTail": "pair-a",
                "channelStable": False,
            }
        )
        result = triage._chaos_oracle_violations(accepted_twice, oracle)
        self.assertTrue(result["replay_dedup"])
        self.assertTrue(result["transcript_ui"])
        self.assertTrue(result["ordering"])
        self.assertTrue(result["identity"])

    @staticmethod
    def _checkpoint(
        checkpoint: str,
        db_ids: tuple[str, str],
        timestamps: tuple[int, int],
    ) -> tuple[dict[str, object], ...]:
        return (
            {
                "tag": "soakOracleCheckpoint",
                "checkpoint": checkpoint,
                "ownerTail": "owner-a",
                "peerTail": "peer-a",
                "pairedAtTail": "pair-a",
                "channelStable": True,
            },
            {
                "tag": "soakOracleDb",
                "checkpoint": checkpoint,
                "id": db_ids[0],
                "seq": 0,
                "tsMs": timestamps[0],
            },
            {
                "tag": "soakOracleDb",
                "checkpoint": checkpoint,
                "id": db_ids[1],
                "seq": 1,
                "tsMs": timestamps[1],
            },
            {
                "tag": "soakOracleUi",
                "checkpoint": checkpoint,
                "id": "a",
                "index": 0,
            },
            {
                "tag": "soakOracleUi",
                "checkpoint": checkpoint,
                "id": "b",
                "index": 1,
            },
        )


if __name__ == "__main__":
    unittest.main()
