import Foundation

public struct PrivilegedHelperConnectionConfig: Sendable, Equatable {
    public let runtimeDirectoryPath: String
    public let socketPath: String
    public let helperLogPath: String
    public let helperPIDPath: String
    public let expectedUID: Int32?

    public init(
        runtimeDirectoryPath: String,
        socketPath: String,
        helperLogPath: String,
        helperPIDPath: String,
        expectedUID: Int32? = nil
    ) {
        self.runtimeDirectoryPath = runtimeDirectoryPath
        self.socketPath = socketPath
        self.helperLogPath = helperLogPath
        self.helperPIDPath = helperPIDPath
        self.expectedUID = expectedUID
    }

    public static func `default`(
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        expectedUID: Int32? = nil
    ) -> PrivilegedHelperConnectionConfig {
        let runtimeDirectory = temporaryDirectory
            .appendingPathComponent("PulseBar", isDirectory: true)
            .path

        return PrivilegedHelperConnectionConfig(
            runtimeDirectoryPath: runtimeDirectory,
            socketPath: URL(fileURLWithPath: runtimeDirectory)
                .appendingPathComponent("privileged-helper.sock")
                .path,
            helperLogPath: URL(fileURLWithPath: runtimeDirectory)
                .appendingPathComponent("privileged-helper.log")
                .path,
            helperPIDPath: URL(fileURLWithPath: runtimeDirectory)
                .appendingPathComponent("privileged-helper.pid")
                .path,
            expectedUID: expectedUID
        )
    }
}

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
    public let activeSourceChain: [String]
    public let sourceDiagnostics: [SensorSourceDiagnostic]
    public let timestamp: Date

    public init(
        ok: Bool,
        reading: PowermetricsTemperatureReading?,
        error: String?,
        source: String,
        activeSourceChain: [String] = [],
        sourceDiagnostics: [SensorSourceDiagnostic] = [],
        timestamp: Date = Date()
    ) {
        self.ok = ok
        self.reading = reading
        self.error = error
        self.source = source
        self.activeSourceChain = activeSourceChain
        self.sourceDiagnostics = sourceDiagnostics
        self.timestamp = timestamp
    }

    public static func success(_ reading: PowermetricsTemperatureReading, source: String = "powermetrics") -> Self {
        PrivilegedTemperatureResponse(
            ok: true,
            reading: reading,
            error: nil,
            source: source,
            activeSourceChain: reading.sourceChain,
            sourceDiagnostics: reading.sourceDiagnostics
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

    private enum CodingKeys: String, CodingKey {
        case ok
        case reading
        case error
        case source
        case activeSourceChain
        case sourceDiagnostics
        case timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        reading = try container.decodeIfPresent(PowermetricsTemperatureReading.self, forKey: .reading)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "powermetrics"
        activeSourceChain = try container.decodeIfPresent([String].self, forKey: .activeSourceChain) ?? []
        sourceDiagnostics = try container.decodeIfPresent([SensorSourceDiagnostic].self, forKey: .sourceDiagnostics) ?? []
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ok, forKey: .ok)
        try container.encodeIfPresent(reading, forKey: .reading)
        try container.encodeIfPresent(error, forKey: .error)
        try container.encode(source, forKey: .source)
        try container.encode(activeSourceChain, forKey: .activeSourceChain)
        try container.encode(sourceDiagnostics, forKey: .sourceDiagnostics)
        try container.encode(timestamp, forKey: .timestamp)
    }
}
