"""Shared local snapshot parsing for the CodexGauge SwiftBar plugin."""

from __future__ import annotations

import glob
import json
import os
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, List, Optional


def classify_window(minutes: Optional[int]) -> str:
    if minutes == 300:
        return "five_hour"
    if minutes == 10_080:
        return "weekly"
    if isinstance(minutes, int) and minutes > 0:
        return "custom"
    return "unknown"


def _collect_rate_limits(value: Any) -> Iterable[Dict[str, Any]]:
    if isinstance(value, dict):
        rate_limits = value.get("rate_limits")
        if isinstance(rate_limits, dict):
            yield rate_limits
        for child in value.values():
            yield from _collect_rate_limits(child)
    elif isinstance(value, list):
        for child in value:
            yield from _collect_rate_limits(child)


def _is_main_codex(rate_limits: Dict[str, Any]) -> bool:
    if not isinstance(rate_limits.get("primary"), dict) and not isinstance(
        rate_limits.get("secondary"), dict
    ):
        return False
    limit_id = str(
        rate_limits.get("limit_id") or rate_limits.get("limitId") or ""
    ).lower()
    return not limit_id or limit_id == "codex"


def _number(value: Any) -> Optional[float]:
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    return None


def _parse_window(
    raw: Any,
    slot: str,
    limit_id: str,
    limit_name: Optional[str],
) -> Optional[Dict[str, Any]]:
    if not isinstance(raw, dict):
        return None

    used = None
    for key in ("used_percent", "used_percentage", "utilization"):
        used = _number(raw.get(key))
        if used is not None:
            break
    if used is None:
        return None

    raw_minutes = raw.get("window_minutes")
    minutes = (
        int(raw_minutes)
        if isinstance(raw_minutes, (int, float)) and not isinstance(raw_minutes, bool)
        else None
    )
    reset_number = _number(raw.get("resets_at"))
    kind = classify_window(minutes)
    return {
        "id": f"{limit_id}-{kind}-{slot}",
        "slot": slot,
        "kind": kind,
        "limit_id": limit_id,
        "limit_name": limit_name,
        "remaining": max(0.0, min(100.0, 100.0 - used)),
        "window_minutes": minutes,
        "resets_at": reset_number,
    }


def _snapshot_from_event(
    root: Dict[str, Any], rate_limits: Dict[str, Any]
) -> Optional[Dict[str, Any]]:
    raw_limit_id = rate_limits.get("limit_id") or rate_limits.get("limitId") or ""
    limit_id = str(raw_limit_id) or "codex"
    limit_name = rate_limits.get("limit_name")
    windows: List[Dict[str, Any]] = []
    for slot in ("primary", "secondary"):
        window = _parse_window(rate_limits.get(slot), slot, limit_id, limit_name)
        if window:
            windows.append(window)
    if not windows:
        return None

    order = {"five_hour": 0, "weekly": 1, "custom": 2, "unknown": 3}
    windows.sort(key=lambda window: order.get(window["kind"], 3))
    return {
        "timestamp": root.get("timestamp"),
        "limit_id": limit_id,
        "limit_name": limit_name,
        "plan_type": rate_limits.get("plan_type"),
        "windows": windows,
        "credits": rate_limits.get("credits"),
    }


def parse_jsonl(text: str) -> Optional[Dict[str, Any]]:
    """Return the newest main-Codex snapshot in a JSONL string."""
    for line in reversed(text.splitlines()):
        if '"rate_limits"' not in line:
            continue
        try:
            root = json.loads(line)
        except (TypeError, ValueError):
            continue
        if not isinstance(root, dict):
            continue
        for rate_limits in _collect_rate_limits(root):
            if _is_main_codex(rate_limits):
                snapshot = _snapshot_from_event(root, rate_limits)
                if snapshot:
                    return snapshot
    return None


def _read_tail(path: str, byte_limit: int = 8 * 1024 * 1024) -> str:
    size = os.path.getsize(path)
    with open(path, "rb") as handle:
        if size > byte_limit:
            handle.seek(-byte_limit, os.SEEK_END)
            handle.readline()
        return handle.read().decode("utf-8", errors="replace")


def load_latest_snapshot(
    base: Optional[str] = None, file_limit: int = 16
) -> Optional[Dict[str, Any]]:
    """Read recent local session files without contacting an API."""
    sessions = os.path.expanduser(base or "~/.codex/sessions")
    files = sorted(
        glob.glob(os.path.join(sessions, "**", "rollout-*.jsonl"), recursive=True),
        key=os.path.getmtime,
        reverse=True,
    )
    newest: Optional[Dict[str, Any]] = None
    newest_timestamp = float("-inf")

    for path in files[:file_limit]:
        try:
            candidate = parse_jsonl(_read_tail(path))
        except OSError:
            continue
        if not candidate:
            continue
        event_time = parse_timestamp(candidate.get("timestamp"))
        comparable = event_time.timestamp() if event_time else os.path.getmtime(path)
        if comparable > newest_timestamp:
            newest_timestamp = comparable
            newest = candidate
    return newest


def parse_timestamp(value: Any) -> Optional[datetime]:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def pace_status(window: Dict[str, Any], now: Optional[datetime] = None) -> str:
    reset = _number(window.get("resets_at"))
    minutes = window.get("window_minutes")
    remaining = _number(window.get("remaining"))
    if reset is None or not isinstance(minutes, int) or minutes <= 0 or remaining is None:
        return "unknown"

    current = (now or datetime.now(timezone.utc)).timestamp()
    seconds_left = reset - current
    if seconds_left <= 0:
        return "expired"

    time_percent = max(0.0, min(100.0, seconds_left / (minutes * 60.0) * 100.0))
    gap = remaining - time_percent
    waste_threshold = 24 * 3600.0 if minutes >= 1440 else minutes * 60.0 * 0.2
    tight_threshold = 6 * 3600.0 if minutes >= 1440 else minutes * 60.0 * 0.2
    if remaining <= 10 and seconds_left > tight_threshold:
        return "quota_tight"
    if (seconds_left <= waste_threshold and remaining >= 25) or gap >= 25:
        return "waste_risk"
    if gap >= 15:
        return "use_more"
    if gap <= -20:
        return "ahead"
    return "balanced"


def select_menu_window(
    windows: List[Dict[str, Any]], now: Optional[datetime] = None
) -> Optional[Dict[str, Any]]:
    ranks = {
        "quota_tight": 5,
        "waste_risk": 4,
        "use_more": 3,
        "ahead": 2,
        "balanced": 1,
        "unknown": 0,
        "expired": 0,
    }
    kind_order = {"weekly": 0, "five_hour": 1, "custom": 2, "unknown": 3}
    if not windows:
        return None
    return sorted(
        windows,
        key=lambda window: (
            -ranks.get(pace_status(window, now=now), 0),
            kind_order.get(window.get("kind"), 3),
        ),
    )[0]
