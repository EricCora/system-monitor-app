import Foundation

public struct CompositeTemperatureDataSource: TemperatureDataSource {
    private let primary: TemperatureDataSource
    private let fallback: TemperatureDataSource

    public init(
        primary: TemperatureDataSource,
        fallback: TemperatureDataSource
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    public func readTemperatures() async throws -> PowermetricsTemperatureReading {
        do {
            return try await primary.readTemperatures()
        } catch {
            let primaryMessage = error.localizedDescription
            do {
                return try await fallback.readTemperatures()
            } catch {
                let fallbackMessage = error.localizedDescription
                throw ProviderError.unavailable(
                    "All privileged temperature sources failed (iohid: \(primaryMessage); fallback: \(fallbackMessage))"
                )
            }
        }
    }
}
