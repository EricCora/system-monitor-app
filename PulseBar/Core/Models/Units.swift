import Foundation

public enum MetricUnit: String, Codable, Sendable {
    case percent
    case bytes
    case bytesPerSecond
    case celsius
    case milliamps
    case minutes
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
        case .minutes:
            return formatMinutes(value)
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
        return formatter.string(fromByteCount: Int64(max(0, bytes)))
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
        var scaled = max(0, bitsPerSecond)
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

    private static func formatMinutes(_ minutes: Double) -> String {
        let clamped = max(0, Int(minutes.rounded()))
        if clamped >= 60 {
            let hours = clamped / 60
            let remainingMinutes = clamped % 60
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(clamped)m"
    }
}
