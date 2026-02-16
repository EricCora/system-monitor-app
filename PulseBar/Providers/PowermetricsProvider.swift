import Foundation

public struct PowermetricsTemperatureReading: Sendable, Equatable, Codable {
    public let primaryCelsius: Double
    public let maxCelsius: Double
    public let sensorCount: Int

    public init(primaryCelsius: Double, maxCelsius: Double, sensorCount: Int) {
        self.primaryCelsius = primaryCelsius
        self.maxCelsius = maxCelsius
        self.sensorCount = sensorCount
    }
}

public struct PrivilegedTemperatureStatus: Sendable, Equatable {
    public let isEnabled: Bool
    public let sourceDescription: String
    public let lastSuccessAt: Date?
    public let lastErrorMessage: String?
    public let nextRetryAt: Date?
    public let healthy: Bool

    public init(
        isEnabled: Bool,
        sourceDescription: String,
        lastSuccessAt: Date?,
        lastErrorMessage: String?,
        nextRetryAt: Date?,
        healthy: Bool
    ) {
        self.isEnabled = isEnabled
        self.sourceDescription = sourceDescription
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
            sensorCount: allTemps.count
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
        let primaryArgs = try await preferredSamplerArguments()
        do {
            let output = try await runner.run(
                command: "/usr/bin/powermetrics",
                arguments: primaryArgs,
                timeoutSeconds: 6
            )
            return try parser.parse(output)
        } catch {
            // One controlled fallback to avoid long multi-attempt stalls.
            if primaryArgs != ["--show-all", "-n", "1", "-i", "1000"] {
                let fallbackOutput = try await runner.run(
                    command: "/usr/bin/powermetrics",
                    arguments: ["--show-all", "-n", "1", "-i", "1000"],
                    timeoutSeconds: 6
                )
                return try parser.parse(fallbackOutput)
            }
            throw error
        }
    }

    private func preferredSamplerArguments() async throws -> [String] {
        let helpOutput = (try? await runner.run(
            command: "/usr/bin/powermetrics",
            arguments: ["--help"],
            timeoutSeconds: 2
        ))?.lowercased()

        if let helpOutput, helpOutput.contains("\n    thermal") {
            return ["--samplers", "thermal", "-n", "1", "-i", "1000"]
        }
        if let helpOutput, helpOutput.contains("\n    smc") {
            return ["--samplers", "smc", "-n", "1", "-i", "1000"]
        }
        // Safe compatibility fallback for unknown tool variants.
        return ["--show-all", "-n", "1", "-i", "1000"]
    }
}

public struct SystemPrivilegedCommandRunner: PrivilegedCommandRunner {
    public init() {}

    public func run(command: String, arguments: [String], timeoutSeconds: TimeInterval) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw ProviderError.unavailable("Failed to launch privileged command: \(error.localizedDescription)")
        }

        let deadline = Date().addingTimeInterval(max(1, timeoutSeconds))
        while process.isRunning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        if process.isRunning {
            process.interrupt()
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        if process.isRunning, process.processIdentifier > 0 {
            kill(process.processIdentifier, SIGKILL)
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let stdErr = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
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
    }

    public func currentStatus() -> PrivilegedTemperatureStatus {
        PrivilegedTemperatureStatus(
            isEnabled: isEnabled,
            sourceDescription: "privileged helper",
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
}
