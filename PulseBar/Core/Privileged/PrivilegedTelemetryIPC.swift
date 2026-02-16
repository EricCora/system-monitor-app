import Foundation

public struct PrivilegedTemperatureRequest: Codable, Sendable, Equatable {
    public enum Command: String, Codable, Sendable {
        case sample
    }

    public let command: Command

    public init(command: Command = .sample) {
        self.command = command
    }
}

public struct PrivilegedTemperatureResponse: Codable, Sendable, Equatable {
    public let ok: Bool
    public let reading: PowermetricsTemperatureReading?
    public let error: String?
    public let source: String
    public let timestamp: Date

    public init(
        ok: Bool,
        reading: PowermetricsTemperatureReading?,
        error: String?,
        source: String,
        timestamp: Date = Date()
    ) {
        self.ok = ok
        self.reading = reading
        self.error = error
        self.source = source
        self.timestamp = timestamp
    }

    public static func success(_ reading: PowermetricsTemperatureReading, source: String = "powermetrics") -> Self {
        PrivilegedTemperatureResponse(
            ok: true,
            reading: reading,
            error: nil,
            source: source
        )
    }

    public static func failure(_ error: String, source: String = "powermetrics") -> Self {
        PrivilegedTemperatureResponse(
            ok: false,
            reading: nil,
            error: error,
            source: source
        )
    }
}
