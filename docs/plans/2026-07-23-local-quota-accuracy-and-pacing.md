# Codex Gauge 本地额度准确性与节奏提醒实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `dispatching-parallel-agents` when tasks are genuinely independent; otherwise use `executing-plans`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Codex Gauge 改造成一个可信、低干扰的本机菜单栏工具，准确识别当前 Codex 限额窗口，动态判断额度使用节奏，并在额度可能浪费或过早耗尽时进行本地提醒。

**Architecture:** 使用“本地日志读取 → 限额语义解析 → 快照可信度 → 节奏评估 → 菜单栏/UI/通知”的单向数据流。应用不读取 `auth.json`、不调用私有接口、不自动联网；重置卡数量和到期时间不从本地日志猜测，只提供明确的数据边界和用户主动打开官方 Usage Dashboard 的入口。

**Tech Stack:** Swift 5.9、SwiftUI、AppKit、Observation、UserNotifications、ServiceManagement、Swift Package Manager、XCTest；SwiftBar 兼容层继续使用 Python 3 标准库。

**执行说明（2026-07-23）：** 实机验收发现 macOS 26 上将
`TimelineView` 直接放入 `MenuBarExtra` 标签会让状态栏在启动阶段持续占用
接近 100% CPU。最终实现改为 AppKit `NSStatusItem` 承载 SwiftUI 弹窗，
由 30 秒显示计时器和 60 秒本地读取计时器分别更新时间与快照；产品行为和
测试口径不变。

## Global Constraints

- 支持 macOS 14 及以上，保持菜单栏应用形态和 `LSUIElement=true`。
- 核心数据读取只能访问用户配置的 Codex sessions 目录，不读取令牌、Cookie、浏览器存储或私有聊天正文。
- 不自动发起网络请求；打开官方 Usage Dashboard 只能由用户主动点击触发。
- 不再通过 `codex exec` 消耗额度来刷新数据。
- 所有额度值必须显示数据来源与快照时间；快照过期时禁止继续显示为“实时”。
- `window_minutes=300` 识别为 5 小时窗口，`window_minutes=10080` 识别为周窗口，其他值保留为可显示的自定义窗口。
- `limit_id=codex` 或旧日志中缺少 `limit_id` 的记录属于主 Codex 限额；其他 `limit_id` 作为独立模型限额保留，不覆盖主限额。
- 重置卡与付费 credits 是两个独立概念，不允许共用字段或文案。
- 所有解析、节奏判断和通知条件先写失败测试，再实现最小代码。
- 保留当前四个未提交文件中的本地意图：移除 GitHub 入口、过滤独立 Spark 限额、面向本地使用；实施时必须逐项检查并避免覆盖用户改动。

---

## 一、方案决策

### 1. 产品边界

主产品为原生 `CodexGauge.app`。SwiftBar 版本保留为轻量兼容入口，但只同步“窗口识别、快照时间、错误状态”三个基础能力，不复制原生应用的通知、登录启动和历史功能。

不实施以下能力：

- 自动抓取或逆向调用 ChatGPT/Codex 私有接口。
- 读取 `~/.codex/auth.json`。
- 自动操纵浏览器或 Codex 界面读取重置卡。
- 根据本地数据猜测重置卡数量或到期时间。
- 自动购买 credits、自动使用重置卡或自动执行 Codex 任务。

### 2. 数据来源和可信度

每个显示值携带以下元数据：

```swift
struct SnapshotSource: Equatable, Sendable {
    let sessionFile: URL
    let eventTimestamp: Date
    let fileModificationDate: Date
}
```

快照状态固定为：

```swift
enum SnapshotFreshness: Equatable, Sendable {
    case fresh          // 事件年龄 <= 15 分钟
    case aging          // 15 分钟 < 年龄 <= 2 小时
    case stale          // 年龄 > 2 小时
    case expiredWindow  // 所有带重置时间的窗口均已结束
}
```

规则：

- `fresh`：正常计算节奏和发送提醒。
- `aging`：显示值并增加“可能已变化”标识，允许节奏提示但不发通知。
- `stale`：灰色显示最后已知值，不计算行动建议、不发通知。
- `expiredWindow`：所有带重置时间的窗口均已结束，显示“等待新快照”，不再显示旧剩余额度为当前值。
- 单个窗口是否过期由 `UsagePaceEvaluator` 逐窗口判断；一个已过期窗口不得让另一个仍有效的窗口失效。
- 解析失败、目录不存在、目录无权限、没有额度事件分别显示不同错误。

### 3. 动态节奏状态

节奏计算：

```text
timeRemainingPercent = clamp((resetsAt - now) / (windowMinutes × 60), 0...1) × 100
paceGap = remainingPercent - timeRemainingPercent
```

状态优先级从高到低：

1. `unknown`：没有可靠快照。
2. `expired`：窗口重置时间已过。
3. `quotaTight`：剩余 <= 10%，且距离重置超过 6 小时。
4. `wasteRisk`：距离重置 <= 24 小时且剩余 >= 25%，或 `paceGap >= 25`。
5. `useMore`：`paceGap >= 15`。
6. `aheadOfPace`：`paceGap <= -20`。
7. `balanced`：其余情况。

对应中文文案和颜色：

| 状态 | 文案 | 颜色 | 含义 |
|---|---|---|---|
| unknown | 数据待确认 | 灰 | 不作行动建议 |
| expired | 等待新快照 | 灰 | 旧窗口已经结束 |
| quotaTight | 额度紧张 | 红 | 控制高消耗任务 |
| wasteRisk | 浪费风险 | 橙 | 临近重置，应优先使用 |
| useMore | 建议多用 | 蓝 | 消耗进度落后于时间进度 |
| aheadOfPace | 使用偏快 | 黄 | 消耗进度领先于时间进度 |
| balanced | 节奏正常 | 绿 | 额度与时间基本匹配 |

推荐使用速度只作为提示：

- 周窗口：`remainingPercent / remainingDays`，显示“建议每天至少使用约 9 个百分点”。
- 小于一天的窗口：`remainingPercent / remainingHours`，显示“建议每小时至少使用约 6 个百分点”。
- 剩余时间不足 15 分钟时不显示推荐速度。

### 4. 通知策略

默认开启以下本地通知：

- 额度紧张：第一次进入 `quotaTight`。
- 浪费风险 48 小时：距离重置首次进入 48 小时以内，且剩余 >= 35%。
- 浪费风险 24 小时：距离重置首次进入 24 小时以内，且剩余 >= 25%。
- 浪费风险 6 小时：距离重置首次进入 6 小时以内，且剩余 >= 10%。
- 每日节奏提醒：每天 17:30 检查一次，仅当状态为 `useMore` 或 `wasteRisk` 时提醒。

通知去重键：

```text
<window-kind>|<reset-epoch>|<notification-kind>
```

同一重置周期、同一通知类型只发送一次。快照为 `aging`、`stale` 或 `expiredWindow` 时禁止发送。

### 5. 菜单栏和弹窗信息

菜单栏默认使用自动模式：

- 只有一个窗口：显示该窗口，例如 `周 51% · 5d14h`。
- 有两个窗口：显示严重度更高的窗口；严重度相同优先显示周窗口。
- 快照老化：前缀 `?`。
- 窗口过期：显示 `! 待刷新`。

用户可在设置中选择：

```swift
enum MenuMetricPreference: String, CaseIterable {
    case automatic
    case fiveHour
    case weekly
}
```

弹窗首屏顺序：

1. 当前判断：节奏正常、建议多用、浪费风险或额度紧张。
2. 动态窗口卡片：仅显示实际存在的窗口。
3. credits 余额：只有日志中存在 `credits` 时显示。
4. 重置卡：固定显示“本地日志无权威数据”，提供“打开官方用量页”按钮。
5. 数据来源、事件时间和快照可信度。

官方用量页固定使用：

```text
https://chatgpt.com/codex/settings/usage
```

---

## 二、文件结构

### 新建文件

- `app/Sources/CodexGauge/UsageSnapshot.swift`
  - 限额窗口、credits、来源、快照和错误类型。
- `app/Sources/CodexGauge/RateLimitParser.swift`
  - 解析单行 JSONL、识别主限额和窗口类型。
- `app/Sources/CodexGauge/SessionLogReader.swift`
  - 后台查找最近日志，以固定内存块反向扫描并缓存最近结果。
- `app/Sources/CodexGauge/UsagePace.swift`
  - 节奏计算、状态、推荐使用速度和菜单栏自动选择。
- `app/Sources/CodexGauge/NotificationPolicy.swift`
  - 纯函数通知判定和持久化去重键。
- `app/Sources/CodexGauge/SnapshotHistoryStore.swift`
  - 保存不含聊天内容的脱敏额度历史。
- `app/Sources/CodexGauge/LaunchAtLoginController.swift`
  - 封装 `SMAppService.mainApp`。
- `app/Tests/CodexGaugeTests/Fixtures/legacy-dual-window.jsonl`
- `app/Tests/CodexGaugeTests/Fixtures/current-weekly-only.jsonl`
- `app/Tests/CodexGaugeTests/Fixtures/spark-before-main.jsonl`
- `app/Tests/CodexGaugeTests/Fixtures/malformed-lines.jsonl`
- `app/Tests/CodexGaugeTests/UsageSnapshotTests.swift`
- `app/Tests/CodexGaugeTests/RateLimitParserTests.swift`
- `app/Tests/CodexGaugeTests/SessionLogReaderTests.swift`
- `app/Tests/CodexGaugeTests/UsagePaceTests.swift`
- `app/Tests/CodexGaugeTests/NotificationPolicyTests.swift`
- `app/Tests/CodexGaugeTests/SnapshotHistoryStoreTests.swift`
- `swiftbar/codex_gauge_core.py`
- `swiftbar/tests/test_codex_gauge_core.py`

### 修改文件

- `app/Package.swift`
  - 增加测试 target 和 fixture resources。
- `app/Sources/CodexGauge/UsageModel.swift`
  - 改为异步协调器，移除内嵌解析和主动查询。
- `app/Sources/CodexGauge/CodexGaugeApp.swift`
  - 使用时间线刷新菜单栏倒计时。
- `app/Sources/CodexGauge/PopoverView.swift`
  - 动态窗口、节奏判断、重置卡边界和数据状态。
- `app/Sources/CodexGauge/SettingsView.swift`
  - 通知、每日提醒、菜单栏指标和登录启动设置。
- `app/Sources/CodexGauge/Theme.swift`
  - 增加动态状态颜色。
- `app/Sources/CodexGauge/Loc.swift`
  - 保持代码式中英文文案接口，补齐新文案。
- `swiftbar/codex-gauge.1m.py`
  - 使用独立核心模块，修正窗口识别和快照年龄。
- `README.md`
  - 更新本地快照边界、共享用量说明和重置卡限制。

---

## 三、开发里程碑

### Milestone 1：数据准确性

完成 Task 1–4 后，应用必须能正确显示当前单周窗口、旧版双窗口和独立模型限额，并明确标识过期或损坏数据。

### Milestone 2：利用率提醒

完成 Task 5–7 后，应用必须能根据时间和额度动态显示状态，发送去重后的本地通知，并支持登录启动。

### Milestone 3：长期可靠性

完成 Task 8–10 后，应用必须具备脱敏趋势、SwiftBar 基础一致性、完整构建测试和准确文档。

---

## Task 1：建立领域模型和测试基础

**Files:**
- Modify: `app/Package.swift`
- Create: `app/Sources/CodexGauge/UsageSnapshot.swift`
- Create: `app/Tests/CodexGaugeTests/UsageSnapshotTests.swift`

**Interfaces:**
- Consumes: 无。
- Produces: `UsageWindowKind`、`UsageWindowSnapshot`、`CreditsSnapshot`、`UsageSnapshot`、`SnapshotSource`、`SnapshotFreshness`、`UsageDataError`。

- [ ] **Step 1: 在 Package.swift 增加测试 target**

将 targets 改为：

```swift
targets: [
    .executableTarget(
        name: "CodexGauge",
        path: "Sources/CodexGauge"
    ),
    .testTarget(
        name: "CodexGaugeTests",
        dependencies: ["CodexGauge"],
        path: "Tests/CodexGaugeTests"
    )
]
```

- [ ] **Step 2: 写窗口分类失败测试**

```swift
import XCTest
@testable import CodexGauge

final class UsageSnapshotTests: XCTestCase {
    func testClassifiesKnownAndCustomWindows() {
        XCTAssertEqual(UsageWindowKind(minutes: 300), .fiveHour)
        XCTAssertEqual(UsageWindowKind(minutes: 10_080), .weekly)
        XCTAssertEqual(UsageWindowKind(minutes: 1_440), .custom(minutes: 1_440))
        XCTAssertEqual(UsageWindowKind(minutes: nil), .unknown)
    }

    func testClampsRemainingPercent() {
        XCTAssertEqual(UsageWindowSnapshot.clampedRemaining(fromUsedPercent: -5), 100)
        XCTAssertEqual(UsageWindowSnapshot.clampedRemaining(fromUsedPercent: 49), 51)
        XCTAssertEqual(UsageWindowSnapshot.clampedRemaining(fromUsedPercent: 120), 0)
    }
}
```

- [ ] **Step 3: 运行测试并确认失败**

Run:

```bash
cd app
swift test --filter UsageSnapshotTests
```

Expected: FAIL，错误包含 `cannot find 'UsageWindowKind' in scope`。

- [ ] **Step 4: 新建 UsageSnapshot.swift**

```swift
import Foundation

enum UsageWindowKind: Hashable, Sendable {
    case fiveHour
    case weekly
    case custom(minutes: Int)
    case unknown

    init(minutes: Int?) {
        switch minutes {
        case 300: self = .fiveHour
        case 10_080: self = .weekly
        case let value?: self = .custom(minutes: value)
        case nil: self = .unknown
        }
    }
}

struct UsageWindowSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let kind: UsageWindowKind
    let limitID: String
    let limitName: String?
    let remainingPercent: Double
    let windowMinutes: Int?
    let resetsAt: Date?

    static func clampedRemaining(fromUsedPercent used: Double) -> Double {
        max(0, min(100, 100 - used))
    }
}

struct CreditsSnapshot: Equatable, Sendable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: Decimal?
}

struct SnapshotSource: Equatable, Sendable {
    let sessionFile: URL
    let eventTimestamp: Date
    let fileModificationDate: Date
}

struct UsageSnapshot: Equatable, Sendable {
    let planType: String?
    let windows: [UsageWindowSnapshot]
    let credits: CreditsSnapshot?
    let source: SnapshotSource
}

enum SnapshotFreshness: Equatable, Sendable {
    case fresh
    case aging
    case stale
    case expiredWindow
}

enum UsageDataError: LocalizedError, Equatable {
    case directoryMissing
    case permissionDenied
    case noSessionFiles
    case noRateLimitEvents
    case unsupportedSchema

    var errorDescription: String? {
        switch self {
        case .directoryMissing: "Codex 会话目录不存在"
        case .permissionDenied: "没有读取 Codex 会话目录的权限"
        case .noSessionFiles: "尚未找到 Codex 会话文件"
        case .noRateLimitEvents: "尚未找到额度快照"
        case .unsupportedSchema: "额度数据格式暂不支持"
        }
    }
}
```

- [ ] **Step 5: 运行测试并确认通过**

Run:

```bash
swift test --filter UsageSnapshotTests
```

Expected: PASS，2 tests passed。

- [ ] **Step 6: 提交领域模型**

```bash
git add app/Package.swift app/Sources/CodexGauge/UsageSnapshot.swift app/Tests/CodexGaugeTests/UsageSnapshotTests.swift
git commit -m "test: define quota snapshot domain model"
```

---

## Task 2：实现主 Codex 限额解析

**Files:**
- Modify: `app/Package.swift`
- Create: `app/Sources/CodexGauge/RateLimitParser.swift`
- Create: `app/Tests/CodexGaugeTests/Fixtures/legacy-dual-window.jsonl`
- Create: `app/Tests/CodexGaugeTests/Fixtures/current-weekly-only.jsonl`
- Create: `app/Tests/CodexGaugeTests/Fixtures/spark-before-main.jsonl`
- Create: `app/Tests/CodexGaugeTests/Fixtures/malformed-lines.jsonl`
- Create: `app/Tests/CodexGaugeTests/RateLimitParserTests.swift`

**Interfaces:**
- Consumes: `UsageSnapshot` domain types from Task 1.
- Produces: `RateLimitEvent` and `RateLimitParser.latestMainEvent(in:)`.

- [ ] **Step 1: 添加四类脱敏 fixture**

先在 `app/Package.swift` 的 `CodexGaugeTests` target 增加：

```swift
resources: [.process("Fixtures")]
```

`legacy-dual-window.jsonl` 包含：

```json
{"timestamp":"2026-07-12T10:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","plan_type":"pro","primary":{"used_percent":12.0,"window_minutes":300,"resets_at":1783872198},"secondary":{"used_percent":28.0,"window_minutes":10080,"resets_at":1784354535}}}}
```

`current-weekly-only.jsonl` 包含：

```json
{"timestamp":"2026-07-23T10:16:49.592Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","plan_type":"pro","primary":{"used_percent":49.0,"window_minutes":10080,"resets_at":1785287160},"secondary":null,"credits":{"has_credits":false,"unlimited":false,"balance":"0"}}}}
```

`spark-before-main.jsonl` 按时间顺序包含：

```json
{"timestamp":"2026-07-23T10:16:40Z","payload":{"rate_limits":{"limit_id":"codex","primary":{"used_percent":40.0,"window_minutes":10080,"resets_at":1785287160}}}}
{"timestamp":"2026-07-23T10:16:50Z","payload":{"rate_limits":{"limit_id":"codex_bengalfox","limit_name":"GPT-5.3-Codex-Spark","primary":{"used_percent":0.0,"window_minutes":300,"resets_at":1785300000}}}}
```

`malformed-lines.jsonl` 包含：

```text
not-json
{"timestamp":"invalid","payload":{"rate_limits":null}}
{"timestamp":"2026-07-23T10:16:49Z","payload":{"rate_limits":{"limit_id":"codex","primary":{"window_minutes":10080}}}}
```

- [ ] **Step 2: 写解析失败测试**

```swift
import XCTest
@testable import CodexGauge

final class RateLimitParserTests: XCTestCase {
    func testParsesLegacyDualWindowByMinutes() throws {
        let event = try fixture("legacy-dual-window").parsedMainEvent()
        XCTAssertEqual(event.windows.map(\.kind), [.fiveHour, .weekly])
        XCTAssertEqual(event.windows.map(\.remainingPercent), [88, 72])
    }

    func testParsesCurrentWeeklyOnlyWithoutMislabelingAsFiveHour() throws {
        let event = try fixture("current-weekly-only").parsedMainEvent()
        XCTAssertEqual(event.windows.count, 1)
        XCTAssertEqual(event.windows[0].kind, .weekly)
        XCTAssertEqual(event.windows[0].remainingPercent, 51)
        XCTAssertNil(event.windows.first { $0.kind == .fiveHour })
    }

    func testIgnoresNewerIndependentModelLimitForMainSnapshot() throws {
        let event = try fixture("spark-before-main").parsedMainEvent()
        XCTAssertEqual(event.limitID, "codex")
        XCTAssertEqual(event.windows[0].remainingPercent, 60)
    }

    func testMalformedInputDoesNotProduceSnapshot() throws {
        XCTAssertNil(try fixture("malformed-lines").parsedOptionalMainEvent())
    }
}
```

测试辅助方法固定使用以下代码，避免依赖当前工作目录：

```swift
private extension RateLimitParserTests {
    func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "jsonl")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private extension String {
    func parsedMainEvent() throws -> RateLimitEvent {
        try XCTUnwrap(RateLimitParser.latestMainEvent(in: self))
    }

    func parsedOptionalMainEvent() throws -> RateLimitEvent? {
        RateLimitParser.latestMainEvent(in: self)
    }
}
```

- [ ] **Step 3: 运行解析测试并确认失败**

Run:

```bash
swift test --filter RateLimitParserTests
```

Expected: FAIL，错误包含 `RateLimitParser` 或 `parsedMainEvent` 未定义。

- [ ] **Step 4: 实现 RateLimitParser**

公开接口：

```swift
struct RateLimitEvent: Equatable, Sendable {
    let timestamp: Date
    let limitID: String
    let limitName: String?
    let planType: String?
    let windows: [UsageWindowSnapshot]
    let credits: CreditsSnapshot?
}

enum RateLimitParser {
    static func latestMainEvent(in jsonl: String) -> RateLimitEvent? {
        for line in jsonl.split(separator: "\n").reversed() {
            guard let data = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let timestampText = root["timestamp"] as? String,
                  let timestamp = ISO8601DateFormatter.codex.date(from: timestampText),
                  let rateLimits = findRateLimits(in: root),
                  isMainCodex(rateLimits),
                  let event = makeEvent(rateLimits, timestamp: timestamp)
            else { continue }
            return event
        }
        return nil
    }

    static func isMainCodex(_ rateLimits: [String: Any]) -> Bool {
        let value = ((rateLimits["limit_id"] as? String)
            ?? (rateLimits["limitId"] as? String)
            ?? "")
            .lowercased()
        return value.isEmpty || value == "codex"
    }
}
```

`makeEvent` 必须：

- 遍历 `primary` 和 `secondary`，但只使用各窗口自己的 `window_minutes` 分类。
- 缺少 `used_percent`、`used_percentage` 或 `utilization` 时跳过该窗口。
- 将剩余比例限制在 `0...100`。
- 按 `.fiveHour`、`.weekly`、`.custom`、`.unknown` 排序。
- 支持 `credits.balance` 为字符串或数字。
- 没有任何有效窗口时返回 `nil`。

ISO8601 formatter：

```swift
extension ISO8601DateFormatter {
    static let codex: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
```

解析无毫秒时间时，再使用一个不含 `.withFractionalSeconds` 的 formatter 重试。

- [ ] **Step 5: 运行测试并确认通过**

Run:

```bash
swift test --filter RateLimitParserTests
```

Expected: PASS，4 tests passed。

- [ ] **Step 6: 提交解析器**

```bash
git add app/Package.swift app/Sources/CodexGauge/RateLimitParser.swift app/Tests/CodexGaugeTests
git commit -m "fix: classify Codex quota windows by duration"
```

---

## Task 3：实现后台有界日志读取

**Files:**
- Create: `app/Sources/CodexGauge/SessionLogReader.swift`
- Create: `app/Tests/CodexGaugeTests/SessionLogReaderTests.swift`

**Interfaces:**
- Consumes: `RateLimitParser.latestMainEvent(in:)`。
- Produces: `UsageSnapshotProviding.latestSnapshot(path:) async throws -> UsageSnapshot`。

- [ ] **Step 1: 写日志选择和尾部读取失败测试**

测试必须覆盖：

```swift
func testFindsMainSnapshotWhenNewestFileOnlyContainsSparkLimit() async throws
func testReadsRateLimitNearEndOfFileWithoutLoadingLargePrefix() async throws
func testMissingDirectoryThrowsDirectoryMissing() async
func testDirectoryWithNoSessionsThrowsNoSessionFiles() async
func testSessionsWithoutRateLimitsThrowsNoRateLimitEvents() async
```

大型前缀测试创建一个 12 MB 临时文件，前 11 MB 为合法但无额度事件的 JSONL，最后一行放主 Codex 快照；测试成功后删除临时目录。

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
swift test --filter SessionLogReaderTests
```

Expected: FAIL，错误包含 `SessionLogReader` 未定义。

- [ ] **Step 3: 实现 provider 协议和 reader actor**

```swift
protocol UsageSnapshotProviding: Sendable {
    func latestSnapshot(path: String) async throws -> UsageSnapshot
}

private struct CachedRateLimitEvent: Sendable {
    let fileSize: UInt64
    let event: RateLimitEvent?
}

actor SessionLogReader: UsageSnapshotProviding {
    private let fileManager: FileManager
    private let chunkSize = 1_048_576
    private var cache: [URL: CachedRateLimitEvent] = [:]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func latestSnapshot(path: String) async throws -> UsageSnapshot {
        let directory = URL(
            fileURLWithPath: (path as NSString).expandingTildeInPath,
            isDirectory: true
        )
        let candidates = try newestSessionFiles(in: directory)
        for candidate in candidates {
            if let event = try latestMainEvent(in: candidate.url) {
                return UsageSnapshot(
                    planType: event.planType,
                    windows: event.windows,
                    credits: event.credits,
                    source: SnapshotSource(
                        sessionFile: candidate.url,
                        eventTimestamp: event.timestamp,
                        fileModificationDate: candidate.modificationDate
                    )
                )
            }
        }
        throw UsageDataError.noRateLimitEvents
    }
}
```

反向扫描使用以下有界跨块辅助方法：

```swift
private extension Data {
    func prefix(upToFirstNewlineOr maximumBytes: Int) -> Data {
        if let newline = firstIndex(of: 0x0A) {
            let prefix = self[..<newline]
            return prefix.count <= maximumBytes ? Data(prefix) : Data()
        }
        return count <= maximumBytes ? self : Data()
    }
}
```

`newestSessionFiles` 必须只收集文件名以 `rollout-` 开头且扩展名为 `.jsonl` 的文件，并按修改时间倒序。

`latestMainEvent(in:)` 必须从文件末尾按 1 MB 固定内存块反向扫描：

```swift
private func latestMainEvent(in url: URL) throws -> RateLimitEvent? {
    let attributes = try fileManager.attributesOfItem(atPath: url.path)
    let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    if let cached = cache[url], cached.fileSize == size {
        return cached.event
    }

    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    var end = size
    var suffix = Data()
    while end > 0 {
        let start = end > UInt64(chunkSize) ? end - UInt64(chunkSize) : 0
        try handle.seek(toOffset: start)
        let block = try handle.read(upToCount: Int(end - start)) ?? Data()
        var data = block
        data.append(suffix)

        if let text = String(data: data, encoding: .utf8),
           let event = RateLimitParser.latestMainEvent(in: text) {
            cache[url] = CachedRateLimitEvent(fileSize: size, event: event)
            return event
        }

        if start == 0 { break }
        suffix = data.prefix(upToFirstNewlineOr: 8_192)
        end = start
    }
    cache[url] = CachedRateLimitEvent(fileSize: size, event: nil)
    return nil
}
```

`prefix(upToFirstNewlineOr:)` 只保留跨块的不完整首行，最大 8 KB；超过 8 KB 的单行按不可解析处理。扫描可以覆盖整个候选文件，但峰值解析内存保持在约 1 MB。缓存以文件大小失效，文件未增长时不得重复扫描。文件读取全部发生在 actor 中，不在主线程执行。

- [ ] **Step 4: 运行测试并确认通过**

Run:

```bash
swift test --filter SessionLogReaderTests
```

Expected: PASS，5 tests passed；12 MB 前缀测试能找到末尾事件；单次反向扫描块不超过 1 MB。

- [ ] **Step 5: 提交日志读取器**

```bash
git add app/Sources/CodexGauge/SessionLogReader.swift app/Tests/CodexGaugeTests/SessionLogReaderTests.swift
git commit -m "perf: read recent quota events off the main thread"
```

---

## Task 4：实现快照可信度和时间节奏引擎

**Files:**
- Create: `app/Sources/CodexGauge/UsagePace.swift`
- Create: `app/Tests/CodexGaugeTests/UsagePaceTests.swift`

**Interfaces:**
- Consumes: `UsageWindowSnapshot`、`UsageSnapshot`。
- Produces: `UsagePaceStatus`、`UsagePaceEvaluation`、`UsagePaceEvaluator.evaluate`、`UsageMenuSelector.select`。

- [ ] **Step 1: 写边界测试**

```swift
final class UsagePaceTests: XCTestCase {
    func testWeeklyWindowWithMoreQuotaThanTimeSuggestsUseMore()
    func testHighRemainingWithin24HoursIsWasteRisk()
    func testLowRemainingFarFromResetIsQuotaTight()
    func testNegativeGapIsAheadOfPace()
    func testBalancedWindowStaysBalanced()
    func testPastResetIsExpired()
    func testAgingAndStaleThresholdsUseEventTimestamp()
    func testAutomaticMenuSelectionPrefersHigherSeverityThenWeekly()
}
```

固定 `now`，不使用测试运行时的真实时间。示例：

```swift
let now = Date(timeIntervalSince1970: 1_800_000_000)
let weekly = makeWindow(
    remaining: 70,
    minutes: 10_080,
    resetsAt: now.addingTimeInterval(2 * 86_400)
)
XCTAssertEqual(UsagePaceEvaluator.evaluate(weekly, now: now).status, .wasteRisk)
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
swift test --filter UsagePaceTests
```

Expected: FAIL，错误包含 `UsagePaceEvaluator` 未定义。

- [ ] **Step 3: 实现节奏状态**

```swift
enum UsagePaceStatus: Int, Comparable, Sendable {
    case unknown = 0
    case balanced = 1
    case aheadOfPace = 2
    case useMore = 3
    case wasteRisk = 4
    case quotaTight = 5
    case expired = 6

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct UsagePaceEvaluation: Equatable, Sendable {
    let status: UsagePaceStatus
    let timeRemainingPercent: Double?
    let paceGap: Double?
    let recommendedPointsPerHour: Double?
    let recommendedPointsPerDay: Double?
}
```

评估顺序必须严格遵循方案决策中的优先级。`SnapshotFreshness` 独立计算：

```swift
static func freshness(
    eventTimestamp: Date,
    windows: [UsageWindowSnapshot],
    now: Date
) -> SnapshotFreshness {
    let resetDates = windows.compactMap(\.resetsAt)
    if !resetDates.isEmpty && resetDates.allSatisfy({ $0 <= now }) {
        return .expiredWindow
    }
    let age = now.timeIntervalSince(eventTimestamp)
    if age <= 15 * 60 { return .fresh }
    if age <= 2 * 60 * 60 { return .aging }
    return .stale
}
```

- [ ] **Step 4: 实现菜单栏自动选择**

```swift
enum UsageMenuSelector {
    static func select(
        windows: [UsageWindowSnapshot],
        preference: MenuMetricPreference,
        now: Date
    ) -> UsageWindowSnapshot? {
        switch preference {
        case .fiveHour:
            return windows.first { $0.kind == .fiveHour }
        case .weekly:
            return windows.first { $0.kind == .weekly }
        case .automatic:
            return windows.max { lhs, rhs in
                let left = UsagePaceEvaluator.evaluate(lhs, now: now).status
                let right = UsagePaceEvaluator.evaluate(rhs, now: now).status
                if left == right {
                    return lhs.kind != .weekly && rhs.kind == .weekly
                }
                return left < right
            }
        }
    }
}
```

- [ ] **Step 5: 运行测试并确认通过**

Run:

```bash
swift test --filter UsagePaceTests
```

Expected: PASS，8 tests passed。

- [ ] **Step 6: 提交节奏引擎**

```bash
git add app/Sources/CodexGauge/UsagePace.swift app/Tests/CodexGaugeTests/UsagePaceTests.swift
git commit -m "feat: evaluate quota pace against reset time"
```

---

## Task 5：重构 UsageModel 并移除主动查询

**Files:**
- Modify: `app/Sources/CodexGauge/UsageModel.swift`
- Modify: `app/Sources/CodexGauge/CodexGaugeApp.swift`
- Create: `app/Tests/CodexGaugeTests/UsageModelTests.swift`

**Interfaces:**
- Consumes: `UsageSnapshotProviding`、`UsagePaceEvaluator`、`UsageMenuSelector`。
- Produces: UI 可观察的 `snapshot`、`freshness`、`lastError`、`isRefreshing` 和时间参数化菜单栏文本。

- [ ] **Step 1: 写模型状态失败测试**

测试使用 actor mock provider，覆盖：

```swift
func testRefreshPublishesSnapshotAndFreshness() async
func testRefreshPublishesDirectoryErrorWithoutKeepingFalseFreshState() async
func testMenuTitleUsesWeeklyLabelForWeeklyOnlySnapshot() async
func testMenuTitleShowsWaitingWhenWindowExpired() async
func testChangingRefreshIntervalRestartsTimer() async
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
swift test --filter UsageModelTests
```

Expected: FAIL，因为现有 `UsageModel` 没有 provider 注入和新状态。

- [ ] **Step 3: 将 UsageModel 改为主线程协调器**

目标接口：

```swift
@MainActor
@Observable
final class UsageModel {
    private let provider: any UsageSnapshotProviding
    private var timer: Timer?

    var snapshot: UsageSnapshot?
    var freshness: SnapshotFreshness?
    var lastError: UsageDataError?
    var isRefreshing = false

    init(provider: any UsageSnapshotProviding = SessionLogReader()) {
        self.provider = provider
        Prefs.registerDefaults()
        refresh()
        restartTimer()
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            defer { isRefreshing = false }
            do {
                let value = try await provider.latestSnapshot(path: Prefs.codexPath)
                snapshot = value
                freshness = UsagePaceEvaluator.freshness(
                    eventTimestamp: value.source.eventTimestamp,
                    windows: value.windows,
                    now: Date()
                )
                lastError = nil
            } catch let error as UsageDataError {
                freshness = .stale
                lastError = error
            } catch {
                freshness = .stale
                lastError = .unsupportedSchema
            }
        }
    }
}
```

删除：

- `fiveHour` 和 `weekly` 固定字段。
- `findRateLimits`、`window`、`readLatest`。
- `busy`。
- `forceRefresh()`。
- 初始化时自动请求通知权限的逻辑。

- [ ] **Step 4: 让菜单栏按时间动态更新**

`CodexGaugeApp.swift` 使用 `NSStatusItem`，避免在当前 macOS 上将
`TimelineView` 直接嵌入状态栏标签：

```swift
statusItem?.button?.title = model.menuBarTitle(now: Date())
```

用独立计时器更新标题和状态色；`menuBarTitle(now:)` 必须包含窗口短标签，
禁止只显示无语义百分比。

- [ ] **Step 5: 运行模型和全量测试**

Run:

```bash
swift test
swift build -c debug
```

Expected: 所有测试 PASS，debug build 成功；源码中 `rg -n "forceRefresh|codex exec" app/Sources` 无结果。

- [ ] **Step 6: 提交模型重构**

```bash
git add app/Sources/CodexGauge/UsageModel.swift app/Sources/CodexGauge/CodexGaugeApp.swift app/Tests/CodexGaugeTests/UsageModelTests.swift
git commit -m "refactor: drive the app from trusted quota snapshots"
```

---

## Task 6：改造弹窗为动态额度决策面板

**Files:**
- Modify: `app/Sources/CodexGauge/PopoverView.swift`
- Modify: `app/Sources/CodexGauge/Theme.swift`
- Modify: `app/Sources/CodexGauge/Loc.swift`
- Create: `app/Tests/CodexGaugeTests/DisplayFormattingTests.swift`

**Interfaces:**
- Consumes: `UsageModel.snapshot`、`UsagePaceEvaluation`、`SnapshotFreshness`。
- Produces: `PaceSummaryView`、`UsageWindowCard`、`DataFreshnessView`、`AccountUsageBoundaryView`。

- [ ] **Step 1: 写时间和文案格式测试**

覆盖：

```swift
func testCountdownShowsDaysAndHours()
func testCountdownShowsHoursAndMinutes()
func testExactResetTimeUsesLocalTimezone()
func testWeeklyOnlyWindowIsLabeledWeekly()
func testStaleSnapshotUsesUncertainPrefix()
func testExpiredSnapshotDoesNotShowRemainingAsCurrent()
```

示例期望：

```swift
XCTAssertEqual(
    DisplayFormatter.countdown(seconds: 5 * 86_400 + 14 * 3_600),
    "5天14小时"
)
```

- [ ] **Step 2: 运行格式测试并确认失败**

Run:

```bash
swift test --filter DisplayFormattingTests
```

Expected: FAIL，`DisplayFormatter` 未定义。

- [ ] **Step 3: 实现纯格式化器**

```swift
enum DisplayFormatter {
    static func countdown(seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        let days = value / 86_400
        let hours = (value % 86_400) / 3_600
        let minutes = (value % 3_600) / 60
        if days > 0 { return "\(days)天\(hours)小时" }
        if hours > 0 { return "\(hours)小时\(minutes)分钟" }
        return "\(minutes)分钟"
    }
}
```

精确时间使用用户本地时区的 `Date.FormatStyle`：

```swift
date.formatted(
    .dateTime.month(.twoDigits).day(.twoDigits)
        .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
)
```

- [ ] **Step 4: 将两个固定圆环改为动态窗口列表**

`PopoverView` 使用：

```swift
TimelineView(.periodic(from: .now, by: 60)) { context in
    VStack(alignment: .leading, spacing: 12) {
        PaceSummaryView(model: model, now: context.date)
        if let snapshot = model.snapshot {
            ForEach(snapshot.windows) { window in
                UsageWindowCard(window: window, now: context.date)
            }
            if let credits = snapshot.credits {
                CreditsRow(credits: credits)
            }
        } else {
            EmptyOrErrorView(error: model.lastError)
        }
        AccountUsageBoundaryView()
        DataFreshnessView(model: model, now: context.date)
    }
}
```

`AccountUsageBoundaryView` 固定包含：

```swift
Text("重置卡数量与到期时间不在本地日志中")
Button("打开官方用量页") {
    NSWorkspace.shared.open(
        URL(string: "https://chatgpt.com/codex/settings/usage")!
    )
}
```

按钮必须是用户主动点击；视图出现时不得自动打开 URL。

- [ ] **Step 5: 扩展状态颜色**

`Theme` 增加：

```swift
static let info = Color(hex: 0x2563eb)
static let caution = Color(hex: 0xb7791f)
static let muted = Color(hex: 0x7b8490)

static func pace(_ status: UsagePaceStatus) -> Color {
    switch status {
    case .balanced: good
    case .useMore: info
    case .wasteRisk: warn
    case .aheadOfPace: caution
    case .quotaTight: bad
    case .unknown, .expired: muted
    }
}
```

状态不能只依赖颜色，必须同时显示文字和系统图标。

- [ ] **Step 6: 运行测试和截图渲染**

Run:

```bash
swift test
swift run CodexGauge --shot /tmp/codex-gauge-pacing.png
```

Expected: 测试全部 PASS；PNG 可生成；单周 fixture 只显示一个“每周”窗口，不出现空的“5 小时”圆环。

- [ ] **Step 7: 提交 UI 改造**

```bash
git add app/Sources/CodexGauge/PopoverView.swift app/Sources/CodexGauge/Theme.swift app/Sources/CodexGauge/Loc.swift app/Tests/CodexGaugeTests/DisplayFormattingTests.swift
git commit -m "feat: show time-aware quota guidance"
```

---

## Task 7：实现通知去重、每日提醒和登录启动

**Files:**
- Create: `app/Sources/CodexGauge/NotificationPolicy.swift`
- Create: `app/Sources/CodexGauge/LaunchAtLoginController.swift`
- Create: `app/Tests/CodexGaugeTests/NotificationPolicyTests.swift`
- Modify: `app/Sources/CodexGauge/UsageModel.swift`
- Modify: `app/Sources/CodexGauge/SettingsView.swift`

**Interfaces:**
- Consumes: `UsagePaceEvaluation`、`SnapshotFreshness`、`UsageWindowSnapshot`。
- Produces: `QuotaNotificationKind`、`NotificationPolicy.pendingNotifications`、`NotificationLedger`、`LaunchAtLoginController`。

- [ ] **Step 1: 写通知策略失败测试**

覆盖：

```swift
func testNoNotificationForAgingSnapshot()
func testNoNotificationForStaleSnapshot()
func testFortyEightHourWasteReminderRequiresAtLeastThirtyFivePercent()
func testTwentyFourHourWasteReminderRequiresAtLeastTwentyFivePercent()
func testSixHourWasteReminderRequiresAtLeastTenPercent()
func testSameResetCycleAndKindIsDeduplicated()
func testNewResetCycleCanNotifyAgain()
func testDailyReminderOnlyFiresOnceAfter1730ForUseMoreOrWasteRisk()
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
swift test --filter NotificationPolicyTests
```

Expected: FAIL，`NotificationPolicy` 未定义。

- [ ] **Step 3: 实现纯通知策略**

```swift
enum QuotaNotificationKind: String, Sendable {
    case quotaTight
    case waste48Hours
    case waste24Hours
    case waste6Hours
    case dailyPace
}

struct QuotaNotification: Equatable, Sendable {
    let kind: QuotaNotificationKind
    let title: String
    let body: String
    let dedupeKey: String
}
```

`pendingNotifications` 接收 `now`、`freshness`、窗口、节奏状态和已经发送的 key 集合，只返回尚未发送且满足阈值的通知。`dedupeKey` 使用窗口类型、`resetsAt` 秒级 epoch 和通知类型生成。

- [ ] **Step 4: 实现持久化 ledger**

使用单独的 UserDefaults key：

```swift
enum NotificationLedger {
    static let key = "quotaNotificationLedgerV1"

    static func contains(_ value: String) -> Bool
    static func insert(_ value: String)
    static func prune(before cutoff: Date)
}
```

存储值为 `[String: TimeInterval]`。每次启动删除 45 天以前的记录，防止无限增长。

- [ ] **Step 5: 将通知权限改为按需申请**

删除 `UsageModel.init` 中的自动授权请求。只有用户在设置中打开提醒开关时调用：

```swift
UNUserNotificationCenter.current()
    .requestAuthorization(options: [.alert, .sound]) { granted, _ in
        UserDefaults.standard.set(granted, forKey: Prefs.alertKey)
    }
```

发送成功后才写入 ledger；`UNUserNotificationCenter.add` 返回错误时不写入，下一次刷新可以重试。

- [ ] **Step 6: 实现登录启动控制器**

```swift
import ServiceManagement

enum LaunchAtLoginController {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
```

设置页显示注册失败的本地错误文本，不吞掉错误。

- [ ] **Step 7: 增加设置项**

新增：

- “登录后自动启动”，默认关闭。
- “额度节奏提醒”，默认开启。
- “每天 17:30 检查未使用额度”，默认开启。
- “菜单栏显示”，默认自动，可选 5 小时或每周。

删除“Active Query”和“Force Refresh”所有 UI。

- [ ] **Step 8: 运行测试和构建**

Run:

```bash
swift test
swift build -c release
```

Expected: 全部 PASS；release build 成功；设置页不再出现主动查询。

- [ ] **Step 9: 提交通知和登录启动**

```bash
git add app/Sources/CodexGauge app/Tests/CodexGaugeTests/NotificationPolicyTests.swift
git commit -m "feat: add deduplicated quota pacing reminders"
```

---

## Task 8：保存脱敏历史并给出近 24 小时变化

**Files:**
- Create: `app/Sources/CodexGauge/SnapshotHistoryStore.swift`
- Create: `app/Tests/CodexGaugeTests/SnapshotHistoryStoreTests.swift`
- Modify: `app/Sources/CodexGauge/UsageModel.swift`
- Modify: `app/Sources/CodexGauge/PopoverView.swift`

**Interfaces:**
- Consumes: `UsageSnapshot`。
- Produces: `HistoryPoint`、`SnapshotHistoryStore.append`、`SnapshotHistoryStore.change(in:last:)`。

- [ ] **Step 1: 写历史存储失败测试**

覆盖：

```swift
func testHistoryPointContainsNoSessionPathOrChatContent()
func testDoesNotAppendDuplicatePointWithinThirtyMinutes()
func testAppendsWhenRemainingChangesByAtLeastOnePoint()
func testAppendsWhenResetCycleChanges()
func testPrunesPointsOlderThanNinetyDays()
func testComputesTwentyFourHourUsedPercentDelta()
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
swift test --filter SnapshotHistoryStoreTests
```

Expected: FAIL，`SnapshotHistoryStore` 未定义。

- [ ] **Step 3: 实现脱敏记录**

```swift
struct HistoryPoint: Codable, Equatable, Sendable {
    let capturedAt: Date
    let kindKey: String
    let remainingPercent: Double
    let resetsAt: Date?
    let windowMinutes: Int?
}
```

文件位置：

```text
~/Library/Application Support/CodexGauge/history-v1.json
```

追加规则：

- 同一窗口和重置周期，距离上一点不足 30 分钟且变化小于 1 个百分点时不追加。
- `resetsAt` 改变时立即追加。
- 保存后删除 90 天以前的点。
- 使用原子写入。
- 文件中不得出现 session 文件路径、任务 ID、提示词、输出或用户名。

- [ ] **Step 4: 在模型刷新成功后记录**

只在 `freshness == .fresh` 时记录。保存失败只写入本地 debug 日志，不阻断主界面更新。

- [ ] **Step 5: 在弹窗显示近 24 小时变化**

示例：

```text
最近24小时已使用 22 个百分点
按当前节奏预计不会浪费本周期额度
```

没有足够历史时不显示该区域，不显示空占位。

- [ ] **Step 6: 运行测试并提交**

Run:

```bash
swift test
```

Expected: 全部 PASS。

```bash
git add app/Sources/CodexGauge/SnapshotHistoryStore.swift app/Sources/CodexGauge/UsageModel.swift app/Sources/CodexGauge/PopoverView.swift app/Tests/CodexGaugeTests/SnapshotHistoryStoreTests.swift
git commit -m "feat: track sanitized local quota trends"
```

---

## Task 9：修正 SwiftBar 基础兼容层

**Files:**
- Create: `swiftbar/codex_gauge_core.py`
- Create: `swiftbar/tests/test_codex_gauge_core.py`
- Modify: `swiftbar/codex-gauge.1m.py`

**Interfaces:**
- Consumes: 与 Swift parser 相同的 fixture 语义。
- Produces: `load_latest_snapshot(base)`、`classify_window(minutes)`、`format_snapshot(snapshot, now)`。

- [ ] **Step 1: 写 Python 单元测试**

```python
import unittest
from codex_gauge_core import classify_window, parse_jsonl

class CodexGaugeCoreTests(unittest.TestCase):
    def test_weekly_primary_is_not_five_hour(self):
        snapshot = parse_jsonl(WEEKLY_ONLY)
        self.assertEqual(snapshot["windows"][0]["kind"], "weekly")
        self.assertEqual(snapshot["windows"][0]["remaining"], 51)

    def test_spark_limit_does_not_replace_main_codex(self):
        snapshot = parse_jsonl(SPARK_AFTER_MAIN)
        self.assertEqual(snapshot["limit_id"], "codex")

    def test_remaining_is_clamped(self):
        self.assertEqual(parse_jsonl(OVERUSED)["windows"][0]["remaining"], 0)
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
PYTHONPATH=swiftbar python3 -m unittest discover -s swiftbar/tests -v
```

Expected: FAIL，`codex_gauge_core` 不存在。

- [ ] **Step 3: 提取纯 Python 核心**

`codex_gauge_core.py` 必须：

- 使用 `window_minutes` 分类。
- 解析事件 `timestamp` 计算快照年龄。
- 只选择 `limit_id` 为空或为 `codex` 的主快照。
- 有界读取最近 16 个文件的最后 8 MB。
- 剩余比例限制在 `0...100`。
- 窗口过期时返回 `freshness="expired"`。

- [ ] **Step 4: 简化 SwiftBar 入口**

`codex-gauge.1m.py` 只负责：

```python
from codex_gauge_core import load_latest_snapshot, render_swiftbar

snapshot = load_latest_snapshot(os.path.expanduser("~/.codex/sessions"))
print(render_swiftbar(snapshot, time.time()))
```

输出必须按实际窗口显示“5 小时窗”“本周窗”或“自定义窗口”，不得为空窗口生成占位条。

- [ ] **Step 5: 运行 Python 测试和当前输出检查**

Run:

```bash
PYTHONPATH=swiftbar python3 -m unittest discover -s swiftbar/tests -v
python3 swiftbar/codex-gauge.1m.py
```

Expected: 所有 Python 测试 PASS；当前本地周窗口显示为“本周窗”，不再显示为“5 小时窗”。

- [ ] **Step 6: 提交 SwiftBar 修复**

```bash
git add swiftbar/codex_gauge_core.py swiftbar/codex-gauge.1m.py swiftbar/tests
git commit -m "fix: align SwiftBar quota window semantics"
```

---

## Task 10：文档、回归和本机验收

**Files:**
- Modify: `README.md`
- Modify: `app/build.sh` only if release build exposes an actual packaging failure

**Interfaces:**
- Consumes: Tasks 1–9 的完整行为。
- Produces: 可重复构建、准确说明和本机验收证据。

- [ ] **Step 1: 更新 README 的准确性声明**

README 必须明确：

- 本地日志是“最后一次可见快照”，不是账户全局实时接口。
- Codex、ChatGPT Work、Excel 和 Workspace Agents 可能共享 agentic usage。
- 重置卡数量和到期时间不在本地 session `rate_limits` 中。
- credits 和重置卡是独立概念。
- 主动查询已移除。
- `/status` 和官方 Usage Dashboard 是权威复核入口。

删除或改写以下绝对表述：

```text
works even when the Codex app is closed
if Codex isn't running, your quota isn't moving either
up-to-the-second value
```

- [ ] **Step 2: 运行完整自动化验证**

Run:

```bash
cd app
swift test
swift build -c release
cd ..
PYTHONPATH=swiftbar python3 -m unittest discover -s swiftbar/tests -v
python3 swiftbar/codex-gauge.1m.py
git diff --check
```

Expected:

- Swift tests 全部 PASS。
- release build 成功。
- Python tests 全部 PASS。
- SwiftBar 当前输出不误标周窗口。
- `git diff --check` 无输出。

- [ ] **Step 3: 构建本机 app bundle**

Run:

```bash
cd app
./build.sh
codesign --verify --deep --strict CodexGauge.app
```

Expected: `CodexGauge.app` 构建成功，`codesign` 退出码为 0。若 codesign 失败，先修正 `build.sh`，不得继续忽略签名失败。

- [ ] **Step 4: 执行手工验收**

逐项验证：

1. 当前单周窗口只显示“每周”，剩余比例与本地脱敏快照一致。
2. 重置时间同时显示绝对时间和倒计时。
3. 等待一分钟，倒计时发生变化但不读取网络。
4. 临时选择空目录，界面显示“尚未找到 Codex 会话文件”。
5. 临时选择不存在目录，界面显示“目录不存在”。
6. 恢复 sessions 目录，数据自动恢复。
7. 关闭通知后不再请求通知权限或发送通知。
8. 打开每日提醒后，同一周期同一类提醒只出现一次。
9. 点击“打开官方用量页”后打开 `https://chatgpt.com/codex/settings/usage`。
10. 登录启动开关打开、退出并重新登录后，菜单栏应用自动出现。
11. 应用运行 30 分钟，菜单栏无明显卡顿，活动监视器中内存不持续增长。
12. 断网后应用仍能读取和显示本地快照；只有用户点击官方用量页时浏览器显示网络状态。

- [ ] **Step 5: 检查隐私边界**

Run:

```bash
rg -n "auth\\.json|Cookie|Authorization|Bearer|codex exec" app swiftbar README.md
rg -n "chatgpt\\.com" app/Sources
```

Expected:

- 第一条命令无结果。
- 第二条命令只命中用户主动点击的官方 Usage Dashboard URL。

- [ ] **Step 6: 提交文档和验收修正**

```bash
git add README.md app/build.sh
git commit -m "docs: define local quota accuracy boundaries"
```

如果 `app/build.sh` 没有修改，不将它加入提交。

---

## 四、完成定义

计划完成必须同时满足：

- 当前 `primary.window_minutes=10080`、`secondary=null` 的数据只显示为周窗口。
- 旧版 300/10080 双窗口数据能同时显示。
- 独立模型限额不会覆盖主 Codex 限额。
- 所有显示值带有事件时间和可信度。
- 过期快照不会继续作为当前剩余额度展示。
- 菜单栏状态会随时间变化，不依赖额度文件再次写入。
- 浪费风险、额度紧张和每日提醒均按重置周期去重。
- 重置卡数量和到期时间不被猜测，官方用量页只在用户点击后打开。
- credits 与重置卡在模型和界面中完全分开。
- 主动 `codex exec` 刷新已删除。
- Swift 与 Python 自动测试全部通过。
- release build、app bundle 签名验证和 12 项本机验收通过。
- 未覆盖用户当前未提交的本地修改。

## 五、预估投入与推荐执行顺序

| 阶段 | Tasks | 预估 | 可交付结果 |
|---|---|---:|---|
| 准确性 | 1–5 | 1.5–2 天 | 数据可信、窗口不误标、不卡主线程 |
| 利用率 | 6–7 | 1–1.5 天 | 动态状态、浪费提醒、登录启动 |
| 长期可靠性 | 8–10 | 1–1.5 天 | 脱敏趋势、SwiftBar 修复、完整验收 |

推荐先完成 Tasks 1–5 并实际使用半天；确认窗口、快照和菜单栏显示稳定后，再执行提醒和历史部分。整个计划预计 3.5–5 个开发日，不包含公开发布、签名证书申请或 App Store 分发。
