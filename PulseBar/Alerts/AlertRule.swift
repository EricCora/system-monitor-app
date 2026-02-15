import Foundation

public struct AlertRule: Codable, Sendable {
    public let metricID: MetricID
    public let threshold: Double
    public let durationSeconds: Int
    public let isEnabled: Bool

    public init(metricID: MetricID, threshold: Double, durationSeconds: Int, isEnabled: Bool) {
        self.metricID = metricID
        self.threshold = threshold
        self.durationSeconds = durationSeconds
        self.isEnabled = isEnabled
    }

    public static let defaultCPU = AlertRule(
        metricID: .cpuTotalPercent,
        threshold: 85,
        durationSeconds: 30,
        isEnabled: false
    )
}
