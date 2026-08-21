import importlib.util
import sys
import unittest
from pathlib import Path


_SPEC = importlib.util.spec_from_file_location("live_soak", Path(__file__).with_name("live_soak.py"))
assert _SPEC and _SPEC.loader
live_soak = importlib.util.module_from_spec(_SPEC)
sys.modules["live_soak"] = live_soak
_SPEC.loader.exec_module(live_soak)


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

    def test_fault_holds_are_bounded_and_events_do_not_overlap(self) -> None:
        schedule = live_soak.build_schedule(42, 600)
        previous_end = 0
        for event in schedule:
            self.assertGreaterEqual(event.at_seconds, previous_end)
            if event.kind == "fault":
                self.assertGreaterEqual(event.hold_seconds, live_soak.MIN_HOLD_SECONDS)
                self.assertLessEqual(event.hold_seconds, live_soak.MAX_HOLD_SECONDS)
                previous_end = event.at_seconds + event.hold_seconds
            else:
                previous_end = event.at_seconds
        self.assertTrue(all(event.at_seconds < 600 for event in schedule))


if __name__ == "__main__":
    unittest.main()
