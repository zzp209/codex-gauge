#!/usr/bin/env python3
# codex-gauge — a zero-cost macOS menu-bar gauge for your Codex (ChatGPT) usage limits.
#
# It reads the rate-limit snapshot that the Codex CLI already writes to your local
# session logs (~/.codex/sessions/**/rollout-*.jsonl). It NEVER calls any API, never
# touches your token, never spends a single unit of quota. The numbers refresh for
# free whenever Codex actually runs — checking the fuel gauge never burns fuel.
#
# SwiftBar plugin (also works in xbar). Filename "*.1m.py" => refresh every 60s,
# which is just a cheap local file read. Manual "refresh" in the menu re-reads too.
#
# MIT
import time
from datetime import datetime, timezone

from codex_gauge_core import (
    load_latest_snapshot,
    pace_status,
    parse_timestamp,
    select_menu_window,
)

# Status palette only (Smartisan OS: color encodes status, never decoration).
GOOD, WARN, BAD = "#0e8a4f", "#c98a14", "#e0411b"   # green / amber / accent-red

def status_color(rem):
    if rem is None:
        return None
    if rem < 10:
        return BAD
    if rem < 30:
        return WARN
    return GOOD

_FILL = "●◕◑◔○"  # full -> empty quarter-circles
def glyph(rem):
    if rem is None:
        return "○"
    return (_FILL[0] if rem >= 87 else _FILL[1] if rem >= 62 else
            _FILL[2] if rem >= 37 else _FILL[3] if rem >= 12 else _FILL[4])

def bar(rem, n=10):
    if rem is None:
        return "▱" * n
    f = max(0, min(n, int(round(rem / 100 * n))))
    return "▰" * f + "▱" * (n - f)

def reset_str(w):
    ra = w.get("resets_at")
    if not ra:
        return ""
    t = time.localtime(ra)
    return f"{t.tm_mon}/{t.tm_mday} {t.tm_hour:02d}:{t.tm_min:02d}"

def ago(timestamp):
    event = parse_timestamp(timestamp)
    if event is None:
        return "—"
    mins = max(0, (datetime.now(timezone.utc) - event).total_seconds() / 60)
    if mins < 60:
        return f"{mins:.0f} 分钟前"
    if mins < 1440:
        return f"{mins / 60:.0f} 小时前"
    return f"{mins / 1440:.0f} 天前"

def window_label(window):
    kind = window.get("kind")
    if kind == "five_hour":
        return "5 小时窗"
    if kind == "weekly":
        return "本周窗"
    minutes = window.get("window_minutes")
    if isinstance(minutes, int):
        return f"{minutes} 分钟窗"
    return "额度窗"

def pace_label(window):
    labels = {
        "quota_tight": "额度紧张",
        "waste_risk": "即将浪费",
        "use_more": "建议加快使用",
        "ahead": "使用偏快",
        "balanced": "节奏正常",
        "expired": "等待新快照",
        "unknown": "节奏未知",
    }
    return labels[pace_status(window)]

snapshot = load_latest_snapshot()
windows = snapshot.get("windows", []) if snapshot else []
selected = select_menu_window(windows)
plan = (snapshot or {}).get("plan_type") or ""

# ---- menu-bar title: automatically show the window needing attention most ----
title_rem = selected.get("remaining") if selected else None
tcolor = status_color(title_rem)
if title_rem is None:
    print("◌ codex")
else:
    prefix = "周" if selected.get("kind") == "weekly" else ""
    seg = f"{glyph(title_rem)} {prefix}{title_rem:.0f}%"
    print(seg + (f" | color={tcolor}" if tcolor in (WARN, BAD) else ""))
print("---")

if snapshot is None:
    print("还没读到额度 | size=12")
    print("跑过一次 codex 之后就有了 | size=11")
else:
    print(f"Codex 用量{(' · ' + plan) if plan else ''} | size=12")
    print(f"快照 {ago(snapshot.get('timestamp'))} | size=11")
    print("---")
    for w in windows:
        label = window_label(w)
        p = w.get("remaining")
        c = status_color(p)
        col = f" color={c}" if c else ""
        ps = f"{p:.0f}%" if p is not None else "—"
        rs = reset_str(w)
        print(f"{glyph(p)}  {label}   剩 {ps}   ·   {rs} 重置 | size=13{col}")
        print(f"      {bar(p)} | font=Menlo size=12{col}")
        print(f"      {pace_label(w)} | size=10{col}")
print("---")
print("↻ 刷新（重读本地 · 免费） | refresh=true size=12")
print("零消耗:只读本地 session 文件,不碰任何 API / token | size=10")
