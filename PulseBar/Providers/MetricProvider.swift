import Foundation

public protocol MetricProvider: Sendable {
    var providerID: String { get }
    func sample(at date: Date) async throws -> [MetricSample]
}

public enum ProviderError: Error, LocalizedError {
    case unavailable(String)
    case parsingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        case .parsingFailed(let message):
            return message
        }
    }
}
