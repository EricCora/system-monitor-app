import Foundation

public enum MemoryHistoryWindow: String, Codable, CaseIterable, Sendable {
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
            return 1800
        }
    }
}

public struct MemoryHistoryPoint: Sendable, Equatable, Codable {
    public let timestamp: Date
    public let appBytes: Double
    public let wiredBytes: Double
    public let activeBytes: Double
    public let compressedBytes: Double
    public let cacheBytes: Double
    public let freeBytes: Double
    public let totalBytes: Double
    public let pressurePercent: Double

    public init(
        timestamp: Date,
        appBytes: Double,
        wiredBytes: Double,
        activeBytes: Double,
        compressedBytes: Double,
        cacheBytes: Double,
        freeBytes: Double,
        totalBytes: Double,
        pressurePercent: Double
    ) {
        self.timestamp = timestamp
        self.appBytes = appBytes
        self.wiredBytes = wiredBytes
        self.activeBytes = activeBytes
        self.compressedBytes = compressedBytes
        self.cacheBytes = cacheBytes
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
        self.pressurePercent = pressurePercent
    }
}
