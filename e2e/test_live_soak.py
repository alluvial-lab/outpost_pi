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

_NIGHTLY_SPEC = importlib.util.spec_from_file_location(
    "nightly_soak_report",
    Path(__file__).parents[1] / "scripts" / "nightly_soak_report.py",
)
assert _NIGHTLY_SPEC and _NIGHTLY_SPEC.loader
nightly = importlib.util.module_from_spec(_NIGHTLY_SPEC)
_NIGHTLY_SPEC.loader.exec_module(nightly)


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
            "transcript DB rows must match the ChatReady ViewModel projection",
            "canonical server timestamp ordering moved backwards",
            "owner identity silently regenerated during a fault",
            "event['name'] == 'relay_kill'",
            "SOAK_KNOWN_FINDING session_rotation_working",
            "harness.exerciseMultiSessionShape(",
            "SOAK_STATE_SHAPE multi_session_round_trip exercised",
            "_assertEveryMaintainedBubbleRenders(",
            "_renderableProjectionIds(tester)",
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

    def test_nightly_inventory_contains_every_current_known_open_finding(self) -> None:
        manifest = nightly.load_expected(
            Path(__file__).with_name("expected-soak-findings.txt")
        )
        # Current truth: one known-open finding (the post-v0.7.0 reconnect
        # hedge gaps). Update this assertion (and only with a deliberate
        # manifest change) whenever a finding is newly opened or closed.
        self.assertEqual(
            manifest,
            {
                "story-fix-app-reconnect-hedge-auth-boundary-"
                "and-post-adoption-cancel"
            },
        )
        self.assertEqual(manifest, set(live_soak.KNOWN_FINDINGS))

    def test_empty_known_findings_manifest_is_valid(self) -> None:
        # With no known-open findings, observation keys resolve to None instead
        # of crashing the import, and a firing observation shape is unexpected.
        self.assertIsNone(live_soak._known_finding("no-such-open-finding"))
        self.assertTrue(
            all(tid is None for tid in live_soak.FINDING_OBSERVATIONS.values())
        )
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            report_path = Path(tmp) / "report.md"
            live_soak._write_report(
                report_path,
                seed=1,
                duration=300,
                schedule=(),
                runner_status=0,
                triage_outputs=[],
                evaluations=[
                    {
                        "capture": "c.jsonl",
                        "swallow": False,
                        "blank_chat": False,
                        "reconnect_churn": True,
                        "lost_count": 3,
                        "missing_causes": 0,
                        "expected_churn_clusters": 0,
                        "unexpected_churn_clusters": 2,
                        "exit": 0,
                    }
                ],
                demonstrated_faults=[],
                unexpected=[
                    "c.jsonl has 2 churn cluster(s) outside every scheduled fault window"
                ],
                suspicious=[],
            )
            report = report_path.read_text()
        self.assertIn("no known-open findings tracked", report)
        self.assertIn("UNEXPECTED", report)

    def test_visible_identity_hold_is_not_classified_as_a_swallow(self) -> None:
        visible = live_soak._evaluate_rows(
            [
                {"tag": "msgSend", "id": "m1", "blocked": True},
                {"tag": "sendQueue", "id": "m1", "phase": "held"},
            ]
        )
        absent = live_soak._evaluate_rows(
            [{"tag": "msgSend", "id": "m2", "blocked": True}]
        )

        self.assertFalse(visible["swallow"])
        self.assertTrue(absent["swallow"])

    def test_churn_clusters_reconcile_only_inside_recorded_fault_windows(self) -> None:
        rows = [
            {"tag": "connChannelLost", "ts": "2026-08-23T00:00:10Z"},
            {"tag": "connChannelLost", "ts": "2026-08-23T00:00:15Z"},
            {"tag": "connChannelLost", "ts": "2026-08-23T00:03:00Z"},
            {"tag": "connChannelLost", "ts": "2026-08-23T00:03:05Z"},
        ]
        windows = (
            (
                live_soak.datetime.fromisoformat("2026-08-23T00:00:00+00:00"),
                live_soak.datetime.fromisoformat("2026-08-23T00:01:00+00:00"),
            ),
        )
        evaluation = live_soak._evaluate_rows(rows, windows)
        self.assertEqual(evaluation["expected_churn_clusters"], 1)
        self.assertEqual(evaluation["unexpected_churn_clusters"], 1)
        self.assertTrue(evaluation["reconnect_churn"])

    def test_nightly_reconciliation_reports_new_and_missing_ids(self) -> None:
        new, missing = nightly.reconcile(
            {"expected-a", "expected-b"},
            {
                "known_open": ["expected-a", "new-c"],
                "observed": [],
                "suspicious": [],
                "unexpected": [],
            },
        )
        self.assertEqual(new, ["new-c"])
        self.assertEqual(missing, ["expected-b"])

    def test_nightly_report_fails_closed_for_every_alert_class(self) -> None:
        clean = {
            "known_open": ["expected-a"],
            "observed": [],
            "suspicious": [],
            "unexpected": [],
        }
        empty = {field: [] for field in clean}
        cases = (
            ("clean", clean, [], [], 0, 0),
            ("new inventory", clean, ["new-c"], [], 0, 1),
            ("missing expected", clean, [], ["expected-b"], 0, 1),
            ("runner failure", clean, [], [], 1, 1),
            ("empty findings with runner failure", empty, [], [], 1, 1),
            (
                "unexpected only",
                {**clean, "unexpected": ["environment drift"]},
                [],
                [],
                0,
                1,
            ),
            (
                "suspicious only",
                {**clean, "suspicious": ["expected finding absent: id"]},
                [],
                [],
                0,
                1,
            ),
        )
        for name, findings, new, missing, runner_status, expected in cases:
            with self.subTest(name=name):
                self.assertEqual(
                    nightly.report_status(
                        findings=findings,
                        new=new,
                        missing=missing,
                        runner_status=runner_status,
                    ),
                    expected,
                )

    def test_nightly_summary_retains_bounded_alert_text(self) -> None:
        summary = nightly.render_summary(
            findings={
                "known_open": [],
                "observed": [],
                "suspicious": ["expected finding absent: finding-a"],
                "unexpected": ["environment drift"],
            },
            new=[],
            missing=[],
            runner_status=0,
        )
        self.assertIn("Unexpected invariant/environment findings: `1`", summary)
        self.assertIn("Suspicious targeted absences: `1`", summary)
        self.assertIn("- environment drift", summary)
        self.assertIn("- expected finding absent: finding-a", summary)

    def test_nightly_report_fails_closed_for_unreadable_findings(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            expected = root / "expected.txt"
            expected.write_text("", encoding="utf-8")
            summary = root / "summary.md"
            cases = (
                ("malformed", root / "malformed.json", "not-json"),
                ("missing", root / "missing.json", None),
            )
            for name, findings, contents in cases:
                with self.subTest(name=name):
                    if contents is not None:
                        findings.write_text(contents, encoding="utf-8")
                    original_argv = sys.argv
                    sys.argv = [
                        "nightly_soak_report.py",
                        "--expected",
                        str(expected),
                        "--findings",
                        str(findings),
                        "--summary",
                        str(summary),
                        "--runner-status",
                        "0",
                    ]
                    try:
                        self.assertEqual(nightly.main(), 2)
                    finally:
                        sys.argv = original_argv
                    self.assertIn("Reconciliation failed", summary.read_text())


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
        self.assertTrue(result["transcript_projection"])
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
                "tag": "soakOracleProjection",
                "checkpoint": checkpoint,
                "id": "a",
                "index": 0,
            },
            {
                "tag": "soakOracleProjection",
                "checkpoint": checkpoint,
                "id": "b",
                "index": 1,
            },
        )


if __name__ == "__main__":
    unittest.main()
