import Foundation

public enum MetricUnit: String, Codable, Sendable {
    case percent
    case bytes
    case bytesPerSecond
    case celsius
    case milliamps
    case watts
    case minutes
    case seconds
    case scalar
}

public enum ThroughputDisplayUnit: String, Codable, CaseIterable, Sendable {
    case bytesPerSecond
    case bitsPerSecond

    public var label: String {
        switch self {
        case .bytesPerSecond:
            return "Bytes/s"
        case .bitsPerSecond:
            return "Bits/s"
        }
    }
}

public enum ChartWindow: String, CaseIterable, Codable, Sendable {
    case fifteenMinutes
    case oneHour
    case sixHours
    case oneDay
    case oneWeek
    case oneMonth

    public var seconds: TimeInterval {
        switch self {
        case .fifteenMinutes:
            return 15 * 60
        case .oneHour:
            return 60 * 60
        case .sixHours:
            return 6 * 60 * 60
        case .oneDay:
            return 24 * 60 * 60
        case .oneWeek:
            return 7 * 24 * 60 * 60
        case .oneMonth:
            return 30 * 24 * 60 * 60
        }
    }

    public var bucketSeconds: Int {
        switch self {
        case .fifteenMinutes, .oneHour:
            return 1
        case .sixHours:
            return 30
        case .oneDay:
            return 60
        case .oneWeek:
            return 300
        case .oneMonth:
            return 1_800
        }
    }

    public var label: String {
        switch self {
        case .fifteenMinutes:
            return "15m"
        case .oneHour:
            return "1h"
        case .sixHours:
            return "6h"
        case .oneDay:
            return "1d"
        case .oneWeek:
            return "1w"
        case .oneMonth:
            return "1mo"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .fifteenMinutes:
            return "15 Minutes"
        case .oneHour:
            return "1 Hour"
        case .sixHours:
            return "6 Hours"
        case .oneDay:
            return "1 Day"
        case .oneWeek:
            return "1 Week"
        case .oneMonth:
            return "1 Month"
        }
    }

    public init(legacyRawValue: String) {
        switch legacyRawValue {
        case "fiveMinutes", "fifteenMinutes":
            self = .fifteenMinutes
        case "oneHour":
            self = .oneHour
        case "sixHours":
            self = .sixHours
        case "twentyFourHours", "oneDay":
            self = .oneDay
        case "sevenDays", "oneWeek":
            self = .oneWeek
        case "thirtyDays", "oneMonth":
            self = .oneMonth
        default:
            self = .oneHour
        }
    }
}

public enum TimeWindow: String, CaseIterable, Codable, Sendable {
    case fiveMinutes
    case fifteenMinutes
    case oneHour

    public var seconds: TimeInterval {
        switch self {
        case .fiveMinutes:
            return 5 * 60
        case .fifteenMinutes:
            return 15 * 60
        case .oneHour:
            return 60 * 60
        }
    }

    public var label: String {
        switch self {
        case .fiveMinutes:
            return "5m"
        case .fifteenMinutes:
            return "15m"
        case .oneHour:
            return "1h"
        }
    }

    public var chartWindow: ChartWindow {
        switch self {
        case .fiveMinutes, .fifteenMinutes:
            return .fifteenMinutes
        case .oneHour:
            return .oneHour
        }
    }
}

public enum UnitsFormatter {
    public static func format(
        _ value: Double,
        unit: MetricUnit,
        throughputUnit: ThroughputDisplayUnit = .bytesPerSecond
    ) -> String {
        switch unit {
        case .percent:
            return String(format: "%.0f%%", value)
        case .bytes:
            return formatBytes(value)
        case .bytesPerSecond:
            return formatThroughput(value, displayUnit: throughputUnit)
        case .celsius:
            return String(format: "%.1f C", value)
        case .milliamps:
            return String(format: "%.0f mA", value)
        case .watts:
            return String(format: "%.1f W", value)
        case .minutes:
            return formatMinutes(value)
        case .seconds:
            return formatSeconds(value)
        case .scalar:
            return String(format: "%.2f", value)
        }
    }

    public static func formatBytes(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: sanitizedByteCount(bytes))
    }

    public static func formatThroughput(_ bytesPerSecond: Double, displayUnit: ThroughputDisplayUnit) -> String {
        switch displayUnit {
        case .bytesPerSecond:
            return "\(formatBytes(bytesPerSecond))/s"
        case .bitsPerSecond:
            return "\(formatBits(bytesPerSecond * 8))/s"
        }
    }

    private static func formatBits(_ bitsPerSecond: Double) -> String {
        let units = ["b", "Kb", "Mb", "Gb", "Tb"]
        var scaled = sanitizedNonNegativeMagnitude(bitsPerSecond)
        var unitIndex = 0

        while scaled >= 1000 && unitIndex < units.count - 1 {
            scaled /= 1000
            unitIndex += 1
        }

        if scaled >= 100 {
            return String(format: "%.0f %@", scaled, units[unitIndex])
        }
        return String(format: "%.1f %@", scaled, units[unitIndex])
    }

    private static func sanitizedByteCount(_ bytes: Double) -> Int64 {
        let sanitized = sanitizedNonNegativeMagnitude(bytes)
        if sanitized >= Double(Int64.max) {
            return Int64.max
        }
        return Int64(sanitized)
    }

    private static func sanitizedNonNegativeMagnitude(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return max(0, value)
    }

    private static func formatMinutes(_ minutes: Double) -> String {
        let clamped = max(0, Int(minutes.rounded()))
        if clamped >= 60 {
            let hours = clamped / 60
            let remainingMinutes = clamped % 60
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(clamped)m"
    }

    private static func formatSeconds(_ seconds: Double) -> String {
        let clamped = max(0, Int(seconds.rounded()))
        let days = clamped / 86_400
        let hours = (clamped % 86_400) / 3_600
        let minutes = (clamped % 3_600) / 60
        let remainingSeconds = clamped % 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m \(remainingSeconds)s"
        }
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }
}
