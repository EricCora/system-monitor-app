import Foundation

public struct ThermalStateProvider: MetricProvider {
    public let providerID = "thermal-state"

    public init() {}

    public func sample(at date: Date) async throws -> [MetricSample] {
        let state = ProcessInfo.processInfo.thermalState
        let level = ThermalStateLevel.from(processThermalState: state)

        return [
            MetricSample(
                metricID: .thermalStateLevel,
                timestamp: date,
                value: level.metricValue,
                unit: .scalar
            )
        ]
    }
}
