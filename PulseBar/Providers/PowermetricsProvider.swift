import Foundation

/// Scaffold provider for a future privileged-mode implementation.
/// MVP intentionally does not execute `powermetrics`; this remains opt-in for V1.
public struct PowermetricsProvider: MetricProvider {
    public let providerID = "powermetrics"

    public init() {}

    public func sample(at date: Date) async throws -> [MetricSample] {
        _ = date
        return []
    }
}
