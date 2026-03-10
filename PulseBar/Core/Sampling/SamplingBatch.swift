import Foundation

public struct ProviderFailure: Error, Sendable, Equatable, Identifiable {
    public let providerID: String
    public let timestamp: Date
    public let message: String

    public init(providerID: String, timestamp: Date, message: String) {
        self.providerID = providerID
        self.timestamp = timestamp
        self.message = message
    }

    public var id: String {
        "\(providerID)-\(timestamp.timeIntervalSince1970)-\(message)"
    }
}

public struct SamplingBatch: Sendable {
    public let timestamp: Date
    public let samples: [MetricSample]
    public let failures: [ProviderFailure]

    public init(timestamp: Date, samples: [MetricSample], failures: [ProviderFailure]) {
        self.timestamp = timestamp
        self.samples = samples
        self.failures = failures
    }

    public var isEmpty: Bool {
        samples.isEmpty && failures.isEmpty
    }
}
