import Foundation

public enum MetricHistoryWindow: String, Codable, CaseIterable, Sendable {
    case oneHour
    case twentyFourHours
    case sevenDays
    case thirtyDays

    public var label: String {
        switch self {
        case .oneHour:
            return "1 Hour"
        case .twentyFourHours:
            return "24 Hours"
        case .sevenDays:
            return "7 Days"
        case .thirtyDays:
            return "30 Days"
        }
    }

    public var seconds: TimeInterval {
        switch self {
        case .oneHour:
            return 60 * 60
        case .twentyFourHours:
            return 24 * 60 * 60
        case .sevenDays:
            return 7 * 24 * 60 * 60
        case .thirtyDays:
            return 30 * 24 * 60 * 60
        }
    }

    public var bucketSeconds: Int {
        switch self {
        case .oneHour:
            return 1
        case .twentyFourHours:
            return 60
        case .sevenDays:
            return 300
        case .thirtyDays:
            return 1_800
        }
    }
}

public struct MetricHistoryPoint: Sendable, Equatable, Codable {
    public let timestamp: Date
    public let value: Double
    public let unit: MetricUnit

    public init(timestamp: Date, value: Double, unit: MetricUnit) {
        self.timestamp = timestamp
        self.value = value
        self.unit = unit
    }
}

public enum ChartHistoryRetentionPolicy: String, Codable, CaseIterable, Sendable {
    case thirtyDays

    public var seconds: TimeInterval {
        switch self {
        case .thirtyDays:
            return 30 * 24 * 60 * 60
        }
    }
}
