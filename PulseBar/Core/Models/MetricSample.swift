import Foundation

public struct MetricSample: Sendable, Codable, Equatable {
    public let metricID: MetricID
    public let timestamp: Date
    public let value: Double
    public let unit: MetricUnit

    public init(metricID: MetricID, timestamp: Date, value: Double, unit: MetricUnit) {
        self.metricID = metricID
        self.timestamp = timestamp
        self.value = value
        self.unit = unit
    }
}
