import Foundation

public enum AlertComparison: String, Codable, Sendable {
    case aboveOrEqual
    case belowOrEqual
}

public struct AlertRule: Codable, Sendable {
    public let metricID: MetricID
    public let threshold: Double
    public let durationSeconds: Int
    public let isEnabled: Bool
    public let comparison: AlertComparison

    public init(
        metricID: MetricID,
        threshold: Double,
        durationSeconds: Int,
        isEnabled: Bool,
        comparison: AlertComparison = .aboveOrEqual
    ) {
        self.metricID = metricID
        self.threshold = threshold
        self.durationSeconds = durationSeconds
        self.isEnabled = isEnabled
        self.comparison = comparison
    }

    private enum CodingKeys: String, CodingKey {
        case metricID
        case threshold
        case durationSeconds
        case isEnabled
        case comparison
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metricID = try container.decode(MetricID.self, forKey: .metricID)
        threshold = try container.decode(Double.self, forKey: .threshold)
        durationSeconds = try container.decode(Int.self, forKey: .durationSeconds)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        comparison = try container.decodeIfPresent(AlertComparison.self, forKey: .comparison) ?? .aboveOrEqual
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(metricID, forKey: .metricID)
        try container.encode(threshold, forKey: .threshold)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(comparison, forKey: .comparison)
    }

    public static let defaultCPU = AlertRule(
        metricID: .cpuTotalPercent,
        threshold: 85,
        durationSeconds: 30,
        isEnabled: false,
        comparison: .aboveOrEqual
    )
}
