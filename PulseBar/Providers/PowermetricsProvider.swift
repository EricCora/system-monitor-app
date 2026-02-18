import Foundation

public struct TemperatureSensorReading: Sendable, Equatable, Codable {
    public let name: String
    public let celsius: Double

    public init(name: String, celsius: Double) {
        self.name = name
        self.celsius = celsius
    }
}

public struct PowermetricsTemperatureReading: Sendable, Equatable, Codable {
    public let primaryCelsius: Double
    public let maxCelsius: Double
    public let sensorCount: Int
    public let sensors: [TemperatureSensorReading]
    public let source: String?

    public init(
        primaryCelsius: Double,
        maxCelsius: Double,
        sensorCount: Int,
        sensors: [TemperatureSensorReading] = [],
        source: String? = nil
    ) {
        self.primaryCelsius = primaryCelsius
        self.maxCelsius = maxCelsius
        self.sensorCount = sensorCount
        self.sensors = sensors
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case primaryCelsius
        case maxCelsius
        case sensorCount
        case sensors
        case source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primaryCelsius = try container.decode(Double.self, forKey: .primaryCelsius)
        maxCelsius = try container.decode(Double.self, forKey: .maxCelsius)
        sensorCount = try container.decode(Int.self, forKey: .sensorCount)
        sensors = try container.decodeIfPresent([TemperatureSensorReading].self, forKey: .sensors) ?? []
        source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(primaryCelsius, forKey: .primaryCelsius)
        try container.encode(maxCelsius, forKey: .maxCelsius)
        try container.encode(sensorCount, forKey: .sensorCount)
        try container.encode(sensors, forKey: .sensors)
        try container.encodeIfPresent(source, forKey: .source)
    }
}

public struct PrivilegedTemperatureStatus: Sendable, Equatable {
    public let isEnabled: Bool
    public let sourceDescription: String
    public let latestReading: PowermetricsTemperatureReading?
    public let lastSuccessAt: Date?
    public let lastErrorMessage: String?
    public let nextRetryAt: Date?
    public let healthy: Bool

    public init(
        isEnabled: Bool,
        sourceDescription: String,
        latestReading: PowermetricsTemperatureReading?,
        lastSuccessAt: Date?,
        lastErrorMessage: String?,
        nextRetryAt: Date?,
        healthy: Bool
    ) {
        self.isEnabled = isEnabled
        self.sourceDescription = sourceDescription
        self.latestReading = latestReading
        self.lastSuccessAt = lastSuccessAt
        self.lastErrorMessage = lastErrorMessage
        self.nextRetryAt = nextRetryAt
        self.healthy = healthy
    }
}

public protocol TemperatureDataSource: Sendable {
    func readTemperatures() async throws -> PowermetricsTemperatureReading
}

public protocol PrivilegedCommandRunner: Sendable {
    func run(command: String, arguments: [String], timeoutSeconds: TimeInterval) async throws -> String
}

public struct PowermetricsTemperatureParser: Sendable {
    public init() {}

    public func parse(_ output: String) throws -> PowermetricsTemperatureReading {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let tempLines = lines.filter { line in
            let lower = line.lowercased()
            return lower.contains("temp") || lower.contains("temperature")
        }

        let sourceLines = tempLines.isEmpty ? lines : tempLines
        var allTemps: [Double] = []
        allTemps.reserveCapacity(24)

        let pattern = #"(-?\d+(?:\.\d+)?)\s*(?:°\s*)?[cC]\b"#
        let regex = try NSRegularExpression(pattern: pattern)

        for line in sourceLines {
            let nsLine = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            for match in matches where match.numberOfRanges > 1 {
                let valueRange = match.range(at: 1)
                let raw = nsLine.substring(with: valueRange)
                if let value = Double(raw), value > -50, value < 150 {
                    allTemps.append(value)
                }
            }
        }

        guard let primary = allTemps.first, let maximum = allTemps.max() else {
            throw ProviderError.parsingFailed("No valid Celsius temperatures found in powermetrics output")
        }

        return PowermetricsTemperatureReading(
            primaryCelsius: primary,
            maxCelsius: maximum,
            sensorCount: allTemps.count,
            source: "powermetrics"
        )
    }
}

public struct PowermetricsTemperatureDataSource: TemperatureDataSource {
    private let runner: PrivilegedCommandRunner
    private let parser: PowermetricsTemperatureParser

    public init(
        runner: PrivilegedCommandRunner = SystemPrivilegedCommandRunner(),
        parser: PowermetricsTemperatureParser = PowermetricsTemperatureParser()
    ) {
        self.runner = runner
        self.parser = parser
    }

    public func readTemperatures() async throws -> PowermetricsTemperatureReading {
        let candidateArguments = try await preferredSamplerArguments()
        var failures: [String] = []
        var observedNoCelsiusOutput = false

        for args in candidateArguments {
            do {
                let output = try await runner.run(
                    command: "/usr/bin/powermetrics",
                    arguments: args,
                    timeoutSeconds: 15
                )
                return try parser.parse(output)
            } catch let error as ProviderError {
                switch error {
                case .unavailable(let message):
                    let lower = message.lowercased()
                    if lower.contains("superuser") || lower.contains("permission") {
                        throw error
                    }
                    failures.append(message)
                case .parsingFailed(let message):
                    if message.localizedCaseInsensitiveContains("No valid Celsius temperatures found") {
                        observedNoCelsiusOutput = true
                    }
                    failures.append(message)
                }
            } catch {
                failures.append(error.localizedDescription)
            }
        }

        if observedNoCelsiusOutput {
            throw ProviderError.unavailable(
                "powermetrics on this macOS did not expose Celsius temperature sensors"
            )
        }

        let joinedFailures = failures.isEmpty ? "unknown error" : failures.joined(separator: "; ")
        throw ProviderError.unavailable("powermetrics failed to produce temperature data (\(joinedFailures))")
    }

    private func preferredSamplerArguments() async throws -> [[String]] {
        let helpOutput = (try? await runner.run(
            command: "/usr/bin/powermetrics",
            arguments: ["--help"],
            timeoutSeconds: 2
        ))?.lowercased()

        func supports(_ sampler: String) -> Bool {
            guard let helpOutput else { return false }
            return helpOutput.contains("\n    \(sampler)")
        }

        func args(for samplers: [String]) -> [String] {
            ["--samplers", samplers.joined(separator: ","), "-n", "1", "-i", "1000"]
        }

        var candidates: [[String]] = []

        let hasCPUPower = supports("cpu_power")
        let hasGPUPower = supports("gpu_power")
        let hasANEPower = supports("ane_power")
        let hasThermal = supports("thermal")

        if hasCPUPower && hasGPUPower && hasANEPower {
            candidates.append(args(for: ["cpu_power", "gpu_power", "ane_power"]))
        }
        if hasCPUPower && hasGPUPower {
            candidates.append(args(for: ["cpu_power", "gpu_power"]))
        }
        if hasCPUPower {
            candidates.append(args(for: ["cpu_power"]))
        }
        if hasThermal {
            candidates.append(args(for: ["thermal"]))
        }

        if candidates.isEmpty {
            // Last compatibility fallback when sampler listing is unavailable.
            candidates.append(args(for: ["cpu_power"]))
            candidates.append(args(for: ["thermal"]))
        }

        return candidates
    }
}

public struct SystemPrivilegedCommandRunner: PrivilegedCommandRunner {
    public init() {}

    public func run(command: String, arguments: [String], timeoutSeconds: TimeInterval) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pulsebar-powermetrics-stdout-\(UUID().uuidString).log")
        let errorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pulsebar-powermetrics-stderr-\(UUID().uuidString).log")

        FileManager.default.createFile(atPath: outputURL.path, contents: Data())
        FileManager.default.createFile(atPath: errorURL.path, contents: Data())

        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }

        process.standardOutput = outputHandle
        process.standardError = errorHandle

        do {
            try process.run()
        } catch {
            throw ProviderError.unavailable("Failed to launch privileged command: \(error.localizedDescription)")
        }

        let deadline = Date().addingTimeInterval(max(1, timeoutSeconds))
        var didTimeout = false
        while process.isRunning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        if process.isRunning {
            didTimeout = true
            process.interrupt()
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        if process.isRunning, process.processIdentifier > 0 {
            kill(process.processIdentifier, SIGKILL)
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        process.waitUntilExit()

        let outputData = (try? Data(contentsOf: outputURL)) ?? Data()
        let errorData = (try? Data(contentsOf: errorURL)) ?? Data()
        let stdErr = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            if didTimeout {
                throw ProviderError.unavailable("powermetrics timed out")
            }
            let lowerErr = stdErr.lowercased()
            if lowerErr.contains("operation not permitted")
                || lowerErr.contains("permission")
                || lowerErr.contains("superuser") {
                throw ProviderError.unavailable("powermetrics requires superuser privileges")
            }
            if lowerErr.contains("timed out") || lowerErr.contains("timeout") {
                throw ProviderError.unavailable("powermetrics timed out")
            }
            if lowerErr.contains("unrecognized sampler") {
                throw ProviderError.unavailable("powermetrics sampler unsupported on this macOS version")
            }
            if process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGKILL {
                throw ProviderError.unavailable("powermetrics timed out")
            }
            if stdErr.isEmpty {
                throw ProviderError.unavailable("powermetrics exited with status \(process.terminationStatus)")
            }
            throw ProviderError.unavailable(stdErr)
        }

        guard let output = String(data: outputData, encoding: .utf8) else {
            throw ProviderError.parsingFailed("Unable to decode powermetrics output")
        }
        return output
    }
}

public actor PowermetricsProvider: MetricProvider {
    public nonisolated let providerID = "powermetrics"

    private let dataSource: TemperatureDataSource
    private let minCollectionInterval: TimeInterval

    private var isEnabled = false
    private var cachedReading: PowermetricsTemperatureReading?
    private var lastSuccessAt: Date?
    private var lastErrorMessage: String?
    private var nextRetryAt: Date?
    private var consecutiveFailures = 0
    private var nextAllowedCollectionAt = Date.distantPast
    private var sourceDescription = "privileged helper"

    public init(
        dataSource: TemperatureDataSource = PowermetricsTemperatureDataSource(),
        minCollectionInterval: TimeInterval = 5
    ) {
        self.dataSource = dataSource
        self.minCollectionInterval = max(1, minCollectionInterval)
    }

    public func updateEnabled(_ enabled: Bool) {
        isEnabled = enabled
        lastErrorMessage = nil
        nextRetryAt = nil
        lastSuccessAt = nil
        consecutiveFailures = 0
        sourceDescription = "privileged helper"
    }

    public func currentStatus() -> PrivilegedTemperatureStatus {
        PrivilegedTemperatureStatus(
            isEnabled: isEnabled,
            sourceDescription: sourceDescription,
            latestReading: cachedReading,
            lastSuccessAt: lastSuccessAt,
            lastErrorMessage: lastErrorMessage,
            nextRetryAt: nextRetryAt,
            healthy: isEnabled && lastSuccessAt != nil && lastErrorMessage == nil
        )
    }

    public func requestImmediateRetry() {
        nextRetryAt = nil
        nextAllowedCollectionAt = Date.distantPast
    }

    public func probeNow(at date: Date = Date()) async -> [MetricSample] {
        guard isEnabled else {
            return []
        }

        do {
            let reading = try await dataSource.readTemperatures()
            cachedReading = reading
            sourceDescription = statusSourceDescription(from: reading)
            lastSuccessAt = date
            lastErrorMessage = nil
            nextRetryAt = nil
            consecutiveFailures = 0
            nextAllowedCollectionAt = date.addingTimeInterval(minCollectionInterval)
            return samples(from: reading, at: date)
        } catch {
            consecutiveFailures += 1
            let retryDelay = retryDelaySeconds(forFailureCount: consecutiveFailures)
            nextRetryAt = date.addingTimeInterval(retryDelay)
            nextAllowedCollectionAt = nextRetryAt ?? date.addingTimeInterval(minCollectionInterval)
            lastErrorMessage = error.localizedDescription
            return []
        }
    }

    public func sample(at date: Date) async throws -> [MetricSample] {
        guard isEnabled else {
            return []
        }

        if date < nextAllowedCollectionAt, let cachedReading {
            return samples(from: cachedReading, at: date)
        }

        if let nextRetryAt, date < nextRetryAt {
            return []
        }

        do {
            let reading = try await dataSource.readTemperatures()
            cachedReading = reading
            sourceDescription = statusSourceDescription(from: reading)
            lastSuccessAt = date
            lastErrorMessage = nil
            nextRetryAt = nil
            consecutiveFailures = 0
            nextAllowedCollectionAt = date.addingTimeInterval(minCollectionInterval)
            return samples(from: reading, at: date)
        } catch {
            consecutiveFailures += 1
            let retryDelay = retryDelaySeconds(forFailureCount: consecutiveFailures)
            nextRetryAt = date.addingTimeInterval(retryDelay)
            nextAllowedCollectionAt = nextRetryAt ?? date.addingTimeInterval(minCollectionInterval)
            lastErrorMessage = error.localizedDescription
            return []
        }
    }

    private func samples(from reading: PowermetricsTemperatureReading, at date: Date) -> [MetricSample] {
        [
            MetricSample(
                metricID: .temperaturePrimaryCelsius,
                timestamp: date,
                value: reading.primaryCelsius,
                unit: .celsius
            ),
            MetricSample(
                metricID: .temperatureMaxCelsius,
                timestamp: date,
                value: reading.maxCelsius,
                unit: .celsius
            )
        ]
    }

    private func retryDelaySeconds(forFailureCount failureCount: Int) -> TimeInterval {
        switch failureCount {
        case 1:
            return 5
        case 2:
            return 15
        case 3:
            return 30
        default:
            return 60
        }
    }

    private func statusSourceDescription(from reading: PowermetricsTemperatureReading) -> String {
        guard let source = reading.source?.trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty else {
            return "privileged helper"
        }
        return "privileged helper (\(source))"
    }
}
