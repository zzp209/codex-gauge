<p align="center">
  <img src="app/icon/icon-1024.png" width="118" alt="Codex Gauge icon">
</p>
<h1 align="center">Codex Gauge</h1>
<p align="center">
  <b>Your Codex usage limits, always in the menu bar —<br>without ever spending a token to check them.</b>
</p>
<p align="center">
  <a href="https://github.com/ruby1304/codex-gauge/releases/latest"><img src="https://img.shields.io/github/v/release/ruby1304/codex-gauge?color=0e8a4f" alt="Release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-lightgrey" alt="macOS 14+">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/ruby1304/codex-gauge?color=0e8a4f" alt="MIT License"></a>
  <a href="https://github.com/ruby1304/codex-gauge/stargazers"><img src="https://img.shields.io/github/stars/ruby1304/codex-gauge?style=social" alt="Stars"></a>
</p>
<p align="center">
  <img src="docs/demo.gif" width="430" alt="Codex Gauge compact quota popover">
</p>

A tiny native **macOS menu-bar app** that shows the **Codex (ChatGPT) usage windows actually present in your local snapshot** — including 5-hour and weekly windows — with reset countdowns, freshness, pace guidance, and utilization alerts.

## Why it's different

Most usage trackers **poll an API** on a timer. That spends requests, can trip rate limits, and — for some providers — risks getting your account flagged. **Codex Gauge never makes a single network call.** It reads the rate-limit snapshot that the Codex CLI *already writes to your local session logs*.

> ### A usage meter that doesn't consume usage.

It never touches your token and can keep showing the last trusted snapshot when the Codex app is closed. Snapshot age is always visible so an old value is never presented as live.

## vs. Codex's own usage display

|  | Codex's built-in menu | **Codex Gauge** |
|---|---|---|
| Where | buried in the account menu | **always in your menu bar** |
| Visible when Codex is closed | ✗ | **✓** |
| Look | one line of text | **compact pace summary** |
| Cost to check your usage | — | **zero · pure local read** |
| Low-quota notifications | ✗ | **✓** |

## Features

- **◔ Accurate window gauges** classified by `window_minutes`, rather than assuming `primary` always means 5 hours.
- **⏱ Live reset countdowns** plus the exact local reset time.
- **🎯 Pace guidance** compares remaining quota with remaining time and highlights balanced, under-used, waste-risk, and quota-tight states.
- **🔔 Configurable utilization reminders** separate quota-tight, waste-risk, and weekly daily-pace scenarios, with selectable check time and per-cycle deduplication. Stale snapshots never notify.
- **🧭 Automatic menu-bar metric** shows the window that currently needs attention most, or lets you pin the 5-hour or weekly window.
- **↔️ Compact menu-bar title** keeps only the window and remaining quota (for example, `周 46%`); reset countdowns and exact times stay in the popover.
- **⚡ Event-driven local refresh** reacts to session-log changes immediately and uses a coalesced fallback check only when needed.
- **🕘 Snapshot freshness** distinguishes fresh, aging, stale, and expired-window data.
- **📈 Sanitized 24-hour trend** stores only time, window type, reset cycle, and remaining percentage; session paths and chat content are never written to history.
- **⚙️ Chinese-friendly local settings** with Chinese enabled by default, plus controls for the sessions path, refresh interval, notification policy, menu metric, language, and launch at login.
- **🚀 Reset-card shortcut** opens Cockpit Tools when it is installed, with the official usage page as a fallback.
- **🔒 100% local monitoring** — no automatic network calls and never reads your token.

## Install

### Download (recommended)
1. Grab `CodexGauge.app.zip` from the [**Releases**](https://github.com/ruby1304/codex-gauge/releases) page, unzip, and drag `CodexGauge.app` to `/Applications`.
2. First launch: right-click the app → **Open** (it's open-source and unsigned), or run:
   ```sh
   xattr -dr com.apple.quarantine /Applications/CodexGauge.app
   ```
3. Look at your menu bar — `周 71%`. Click it for the compact quota summary.

### Build from source
```sh
git clone https://github.com/ruby1304/codex-gauge.git
cd codex-gauge/app && ./build.sh run
```
Needs the Swift toolchain (Xcode **Command Line Tools** — no full Xcode required).

## How it works

Every Codex API response carries your current rate-limit state, and the Codex CLI persists it into each session log at `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` as a `rate_limits` object:

```json
{ "rate_limits": {
    "primary":   { "used_percent": 2.0,  "window_minutes": 300,   "resets_at": 1780992992 },
    "secondary": { "used_percent": 29.0, "window_minutes": 10080,  "resets_at": 1781142220 },
    "plan_type": "prolite" } }
```

Codex Gauge classifies each window from `window_minutes` (`300` for 5 hours and `10080` for a week), filters out unrelated limit families such as Spark, finds the newest main-Codex event across recent session logs, and clamps `100 − used_percent` to `0...100`. It only renders windows that are actually present in that event.

**Freshness:** this is a snapshot from the last Codex response written to disk. Time-based resets continue even while Codex is closed, so the app marks aging/stale/expired data clearly and waits for a new trusted snapshot instead of silently treating it as current. “Refresh” only re-reads local files; it does not invoke Codex or spend quota.

**Banked reset cards:** their count and expiry are not included in local session logs. Codex Gauge does not guess or scrape authenticated account data automatically. The popover provides an explicit link to the official Codex usage dashboard when you want to check them.

## Prefer a menu-bar-script setup?

There's also a zero-dependency **SwiftBar / xbar plugin** in [`swiftbar/`](swiftbar/) using the same semantic window classification and main-Codex filtering, if you'd rather not run a standalone app.

## Privacy & safety

- **No automatic network.** Monitoring and refresh only read local files. The official usage dashboard opens only when you click its button.
- **No credentials.** It never reads `~/.codex/auth.json` or any token.
- **Local only.** It reads session-log files you already have. Nothing leaves your machine.

## Credits

- The same local `rate_limits` source is also used by [`xiangz19/codex-ratelimit`](https://github.com/xiangz19/codex-ratelimit) (CLI/TUI).
- App icon generated with Codex's own image model — dogfooding all the way down.

## License

MIT © 2026 ruby1304
