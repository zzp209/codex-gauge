import Foundation

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
                  let timestamp = parseTimestamp(timestampText)
            else { continue }

            for rateLimits in collectRateLimits(in: root) where isMainCodex(rateLimits) {
                if let event = makeEvent(rateLimits, timestamp: timestamp) {
                    return event
                }
            }
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

    private static func parseTimestamp(_ value: String) -> Date? {
        fractionalDateFormatter.date(from: value) ?? basicDateFormatter.date(from: value)
    }

    private static func collectRateLimits(in object: Any) -> [[String: Any]] {
        if let dictionary = object as? [String: Any] {
            var results: [[String: Any]] = []
            if let rateLimits = dictionary["rate_limits"] as? [String: Any] {
                results.append(rateLimits)
            }
            for value in dictionary.values {
                results.append(contentsOf: collectRateLimits(in: value))
            }
            return results
        }
        if let array = object as? [Any] {
            return array.flatMap { collectRateLimits(in: $0) }
        }
        return []
    }

    private static func makeEvent(
        _ rateLimits: [String: Any],
        timestamp: Date
    ) -> RateLimitEvent? {
        let rawLimitID = (rateLimits["limit_id"] as? String)
            ?? (rateLimits["limitId"] as? String)
            ?? ""
        let limitID = rawLimitID.isEmpty ? "codex" : rawLimitID
        let limitName = rateLimits["limit_name"] as? String
        let planType = rateLimits["plan_type"] as? String

        var windows: [UsageWindowSnapshot] = []
        for slot in ["primary", "secondary"] {
            guard let rawWindow = rateLimits[slot] as? [String: Any],
                  let used = number(
                    rawWindow["used_percent"]
                        ?? rawWindow["used_percentage"]
                        ?? rawWindow["utilization"]
                  )
            else { continue }

            let minutes = integer(rawWindow["window_minutes"])
            let resetsAt = number(rawWindow["resets_at"]).map {
                Date(timeIntervalSince1970: $0)
            }
            let kind = UsageWindowKind(minutes: minutes)
            windows.append(
                UsageWindowSnapshot(
                    id: "\(limitID)-\(kind.key)-\(slot)",
                    kind: kind,
                    limitID: limitID,
                    limitName: limitName,
                    remainingPercent: UsageWindowSnapshot.clampedRemaining(
                        fromUsedPercent: used
                    ),
                    windowMinutes: minutes,
                    resetsAt: resetsAt
                )
            )
        }

        guard !windows.isEmpty else { return nil }
        windows.sort { $0.kind.sortOrder < $1.kind.sortOrder }

        return RateLimitEvent(
            timestamp: timestamp,
            limitID: limitID,
            limitName: limitName,
            planType: planType,
            windows: windows,
            credits: parseCredits(rateLimits["credits"])
        )
    }

    private static func parseCredits(_ value: Any?) -> CreditsSnapshot? {
        guard let dictionary = value as? [String: Any] else { return nil }
        let hasCredits = dictionary["has_credits"] as? Bool ?? false
        let unlimited = dictionary["unlimited"] as? Bool ?? false
        let balance: Decimal?
        if let text = dictionary["balance"] as? String {
            balance = Decimal(string: text)
        } else if let number = dictionary["balance"] as? NSNumber {
            balance = Decimal(string: number.stringValue)
        } else {
            balance = nil
        }
        return CreditsSnapshot(
            hasCredits: hasCredits,
            unlimited: unlimited,
            balance: balance
        )
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func integer(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let basicDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
