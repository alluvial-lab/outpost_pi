#!/usr/bin/env python3
"""Summarize and triage Outpost-Pi debug-capture rings.

Capture rings are newline-delimited JSON.  This tool deliberately treats the
ring as untrusted diagnostic input: malformed lines are skipped and only known
content-free fields are rendered.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

TIMELINE_TAGS = {
    "connStatus",
    "connChannelLost",
    "connHydrate",
    "sessionGate",
    "workingConv",
    "msgSend",
    "msgEcho",
    "sendQueue",
    "route",
}
SWALLOW_ID = "cli_01a01fd3-a3a7-760a-9c9e-ecf9676240fd"
SWALLOW_TRACKING_ID = "story-app-send-swallowed-session-identity-unavailable"
BLANK_CHAT_TRACKING_ID = "backlog-app-blank-chat-direct-open"
FIXTURE = (
    Path(__file__).resolve().parent
    / "fixtures"
    / "debug_capture_triage"
    / "cad-11f1-b349-a5efddf14d8d.bin"
)


@dataclass(frozen=True)
class Capture:
    path: Path
    rows: tuple[dict[str, Any], ...]
    malformed: int


def _parse_timestamp(value: Any) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def load_capture(path: Path) -> Capture:
    rows: list[dict[str, Any]] = []
    malformed = 0
    with path.open(encoding="utf-8") as stream:
        for line in stream:
            if not line.strip():
                continue
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                malformed += 1
                continue
            if not isinstance(value, dict) or not isinstance(value.get("tag"), str):
                malformed += 1
                continue
            rows.append(value)
    return Capture(path=path, rows=tuple(rows), malformed=malformed)


def _ordered_rows(rows: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    indexed = list(enumerate(rows))
    indexed.sort(
        key=lambda item: (
            _parse_timestamp(item[1].get("ts"))
            or datetime.max.replace(tzinfo=timezone.utc),
            item[0],
        )
    )
    return [row for _, row in indexed]


def _fmt_ts(row: dict[str, Any]) -> str:
    value = row.get("ts")
    return value if isinstance(value, str) else "?"


def _safe(value: Any) -> str:
    """Render bounded scalar diagnostics without exposing arbitrary payloads."""
    if isinstance(value, (str, int, float, bool)) or value is None:
        return str(value)
    return "?"


def _send_correlations(rows: Iterable[dict[str, Any]]) -> list[tuple[dict[str, Any], bool]]:
    ordered = _ordered_rows(rows)
    echoes: dict[str, list[datetime | None]] = {}
    for row in ordered:
        if row.get("tag") == "msgEcho" and isinstance(row.get("id"), str):
            echoes.setdefault(row["id"], []).append(_parse_timestamp(row.get("ts")))
    result: list[tuple[dict[str, Any], bool]] = []
    for row in ordered:
        if row.get("tag") != "msgSend" or not isinstance(row.get("id"), str):
            continue
        sent_at = _parse_timestamp(row.get("ts"))
        has_later_echo = any(
            echo_at is not None
            and (sent_at is None or echo_at >= sent_at)
            for echo_at in echoes.get(row["id"], [])
        )
        result.append((row, has_later_echo))
    return result


def _clusters(rows: Iterable[dict[str, Any]], window_seconds: int = 60) -> list[list[dict[str, Any]]]:
    channel_lost = [
        row
        for row in _ordered_rows(rows)
        if row.get("tag") == "connChannelLost"
        and _parse_timestamp(row.get("ts")) is not None
    ]
    clusters: list[list[dict[str, Any]]] = []
    for row in channel_lost:
        current_ts = _parse_timestamp(row.get("ts"))
        if not clusters:
            clusters.append([row])
            continue
        previous_ts = _parse_timestamp(clusters[-1][-1].get("ts"))
        if previous_ts is not None and current_ts is not None:
            gap = (current_ts - previous_ts).total_seconds()
        else:
            gap = window_seconds + 1
        if gap <= window_seconds:
            clusters[-1].append(row)
        else:
            clusters.append([row])
    return clusters


def _same_route_projection(left: dict[str, Any], right: dict[str, Any]) -> bool:
    if left.get("room") != right.get("room"):
        return False
    left_session = left.get("sessionIdTail")
    right_session = right.get("sessionIdTail")
    return not (
        isinstance(left_session, str)
        and isinstance(right_session, str)
        and left_session != right_session
    )


def _blank_chat_rows(rows: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    """Find empty hydrates that lost known history and never rendered it."""
    ordered = _ordered_rows(rows)
    result: list[dict[str, Any]] = []
    for index, row in enumerate(ordered):
        if row.get("tag") != "route" or row.get("phase") != "projection-empty":
            continue
        history_existed = any(
            _same_route_projection(candidate, row)
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
            for candidate in ordered[:index]
        )
        if not history_existed:
            continue
        rendered_after_hydrate = any(
            candidate.get("tag") == "route"
            and candidate.get("phase") == "projection-ready"
            and isinstance(candidate.get("messageCount"), int)
            and candidate["messageCount"] > 0
            and _same_route_projection(candidate, row)
            for candidate in ordered[index + 1 :]
        )
        if not rendered_after_hydrate:
            result.append(row)
    return result


def _anomalies(
    capture: Capture,
) -> tuple[list[dict[str, Any]], list[list[dict[str, Any]]], list[dict[str, Any]]]:
    swallow = [
        row
        for row, echoed in _send_correlations(capture.rows)
        if row.get("blocked") is True and not echoed
    ]
    # Empty is legitimate at activation. The bug signature requires prior
    # content-free proof that this session had history and no later non-empty
    # projection showing that the cold hydrate eventually rendered it.
    blank_chat = _blank_chat_rows(capture.rows)
    churn = [cluster for cluster in _clusters(capture.rows) if len(cluster) >= 2]
    return swallow, churn, blank_chat


def _span(rows: Iterable[dict[str, Any]]) -> tuple[datetime | None, datetime | None]:
    times = [
        parsed
        for row in rows
        if (parsed := _parse_timestamp(row.get("ts"))) is not None
    ]
    return (min(times), max(times)) if times else (None, None)


def summarize(capture: Capture) -> tuple[str, bool]:
    rows = capture.rows
    start, end = _span(rows)
    counts = Counter(row.get("tag", "?") for row in rows)
    correlations = _send_correlations(rows)
    no_echo = [(row, echoed) for row, echoed in correlations if not echoed]
    swallow, churn, blank_chat = _anomalies(capture)

    lines = [f"Capture: {capture.path}", f"Rows: {len(rows)}"]
    if start is None or end is None:
        lines.append("Span: unavailable")
    else:
        lines.append(f"Span: {start.isoformat()} -> {end.isoformat()} ({end - start})")
    lines.append("Tag counts:")
    for tag in sorted(counts):
        lines.append(f"  {tag}: {counts[tag]}")
    if capture.malformed:
        lines.append(f"Malformed/skipped: {capture.malformed}")

    lines.append("Message correlation:")
    lines.append(f"  sends: {len(correlations)}; echoes: {counts.get('msgEcho', 0)}")
    lines.append(f"  sends without later echo: {len(no_echo)}")
    for row, _ in no_echo:
        lines.append(
            "  UNCONFIRMED msgSend "
            f"id={_safe(row.get('id'))} blocked={_safe(row.get('blocked', False))}"
        )
    if swallow:
        lines.append(
            f"  SWALLOW signature: {len(swallow)} blocked send(s) without echo "
            f"[{SWALLOW_TRACKING_ID}]"
        )
        for row in swallow:
            lines.append(f"    id={row.get('id')}")
    else:
        lines.append("  SWALLOW signature: none")

    lines.append("Blank-chat signature:")
    if blank_chat:
        lines.append(
            f"  BLANK CHAT signature: {len(blank_chat)} projection-empty route(s) "
            f"[{BLANK_CHAT_TRACKING_ID}]"
        )
    else:
        lines.append("  BLANK CHAT signature: none")

    lifecycle = Counter(
        f"{row.get('operation', '?')}/{row.get('reason', '?')}"
        for row in rows
        if row.get("tag") == "lifecycleFailure"
    )
    lines.append("Lifecycle failure attribution:")
    if lifecycle:
        for attribution in sorted(lifecycle):
            lines.append(f"  {attribution}: {lifecycle[attribution]}")
    else:
        lines.append("  none")

    lost = [row for row in rows if row.get("tag") == "connChannelLost"]
    causes = Counter(
        row.get("cause") or row.get("attribution") or "unknown"
        for row in lost
    )
    lines.append("Connection churn:")
    lines.append(f"  connChannelLost: {len(lost)}")
    lines.append(
        "  cause attribution: "
        + (", ".join(f"{key}={causes[key]}" for key in sorted(causes)) or "none")
    )
    lines.append(f"  clusters (<=60s): {len(churn)} anomalous cluster(s)")
    for index, cluster in enumerate(churn, start=1):
        cluster_causes = Counter(
            row.get("cause") or row.get("attribution") or "unknown" for row in cluster
        )
        detail = ", ".join(
            f"{key}={cluster_causes[key]}" for key in sorted(cluster_causes)
        )
        lines.append(f"    cluster {index}: {len(cluster)} event(s); {detail}")

    anomaly = bool(swallow or churn or blank_chat)
    lines.append("Anomalies: " + ("FOUND" if anomaly else "none"))
    return "\n".join(lines), anomaly


def timeline(capture: Capture) -> tuple[str, bool]:
    swallow, churn, blank_chat = _anomalies(capture)
    swallow_ids = {row.get("id") for row in swallow}
    blank_chat_rows = {id(row) for row in blank_chat}
    lines = [f"Timeline: {capture.path}"]
    for row in _ordered_rows(capture.rows):
        tag = row.get("tag")
        if tag not in TIMELINE_TAGS:
            continue
        fields: list[str] = []
        for key in (
            "status",
            "cause",
            "action",
            "phase",
            "projection",
            "working",
            "id",
            "blocked",
            "outcome",
            "room",
            "sessionIdTail",
            "messageCount",
        ):
            if key in row:
                fields.append(f"{key}={_safe(row[key])}")
        marker = " [SWALLOW]" if row.get("id") in swallow_ids else ""
        if id(row) in blank_chat_rows:
            marker += f" [BLANK CHAT: {BLANK_CHAT_TRACKING_ID}]"
        lines.append(f"{_fmt_ts(row)} {tag}{marker}" + (" " + " ".join(fields) if fields else ""))
    lines.append(
        "Timeline anomalies: "
        f"swallow={len(swallow)}; blank_chat={len(blank_chat)}; "
        f"churn_clusters={len(churn)}"
    )
    return "\n".join(lines), bool(swallow or churn or blank_chat)


def run_selftest() -> int:
    if not FIXTURE.exists():
        print(f"selftest: FAIL missing fixture {FIXTURE}", file=sys.stderr)
        return 1
    capture = load_capture(FIXTURE)
    swallow, churn, blank_chat = _anomalies(capture)
    timeout_count = sum(
        row.get("tag") == "lifecycleFailure"
        and row.get("operation") == "retryConnect"
        and row.get("reason") == "TimeoutException"
        for row in capture.rows
    )
    ids = {row.get("id") for row in swallow}
    legitimate_empty = Capture(
        path=Path("selftest-legitimate-empty"),
        rows=(
            {
                "tag": "route",
                "ts": "2026-08-21T00:00:00Z",
                "room": "new-room",
                "phase": "projection-empty",
                "messageCount": 0,
            },
        ),
        malformed=0,
    )
    checks = {
        "known blocked swallow": SWALLOW_ID in ids,
        "known blank chat after existing history": bool(blank_chat),
        "legitimate activation empty is ignored": not _blank_chat_rows(
            legitimate_empty.rows
        ),
        "89 retryConnect TimeoutExceptions": timeout_count == 89,
        "churn cluster": bool(churn),
    }
    for name, passed in checks.items():
        print(f"selftest: {'PASS' if passed else 'FAIL'} {name}")
    return 0 if all(checks.values()) else 1


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", nargs="?", type=Path, help="NDJSON ring to inspect")
    parser.add_argument("--timeline", action="store_true", help="print the interleaved event timeline")
    parser.add_argument("--selftest", action="store_true", help="run the checked-in regression fixture")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    if args.selftest:
        if args.capture is not None:
            print("--selftest does not accept a capture path", file=sys.stderr)
            return 2
        return run_selftest()
    if args.capture is None:
        print("a capture path is required (or use --selftest)", file=sys.stderr)
        return 2
    try:
        capture = load_capture(args.capture)
    except OSError as error:
        print(f"cannot read {args.capture}: {error}", file=sys.stderr)
        return 2
    output, anomaly = timeline(capture) if args.timeline else summarize(capture)
    print(output)
    return 1 if anomaly else 0


if __name__ == "__main__":
    raise SystemExit(main())
