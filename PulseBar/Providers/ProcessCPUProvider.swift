import Foundation

public actor ProcessCPUProvider {
    public typealias ProcessRunner = @Sendable () throws -> String

    private let maxEntries: Int
    private let processRunner: ProcessRunner
    private var minCollectionInterval: TimeInterval
    private var cachedSnapshot: (timestamp: Date, entries: [CPUProcessEntry])?
    private var lastErrorMessage: String?

    public init(
        maxEntries: Int = 5,
        minCollectionInterval: TimeInterval = 2,
        processRunner: @escaping ProcessRunner = { try ProcessCPUProvider.runPSOutput() }
    ) {
        self.maxEntries = max(1, maxEntries)
        self.minCollectionInterval = max(1, minCollectionInterval)
        self.processRunner = processRunner
    }

    public func topProcesses(at date: Date = Date()) async -> [CPUProcessEntry] {
        if let cachedSnapshot,
           date.timeIntervalSince(cachedSnapshot.timestamp) < minCollectionInterval {
            return cachedSnapshot.entries
        }

        do {
            let output = try processRunner()
            let parsed = Self.parsePSOutput(output, maxEntries: maxEntries)
            cachedSnapshot = (date, parsed)
            lastErrorMessage = nil
            return parsed
        } catch {
            lastErrorMessage = error.localizedDescription
            return cachedSnapshot?.entries ?? []
        }
    }

    public func statusMessage() -> String? {
        lastErrorMessage
    }

    public func updateInterval(seconds: Double) {
        minCollectionInterval = max(1, seconds)
        cachedSnapshot = nil
    }

    static func parsePSOutput(_ output: String, maxEntries: Int) -> [CPUProcessEntry] {
        let safeMax = max(1, maxEntries)
        let lines = output.split(whereSeparator: \.isNewline)
        var entries: [CPUProcessEntry] = []
        entries.reserveCapacity(min(lines.count, safeMax))

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }

            guard let cpuStart = trimmed.firstIndex(where: { !$0.isWhitespace }) else {
                continue
            }
            guard let splitIndex = trimmed[cpuStart...].firstIndex(where: \.isWhitespace) else {
                continue
            }

            let cpuToken = String(trimmed[cpuStart..<splitIndex])
                .replacingOccurrences(of: ",", with: ".")
            guard let cpuPercent = Double(cpuToken), cpuPercent >= 0 else {
                continue
            }

            let nameToken = trimmed[splitIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
            if nameToken.isEmpty {
                continue
            }

            entries.append(CPUProcessEntry(name: nameToken, cpuPercent: cpuPercent))
        }

        return entries
            .sorted { lhs, rhs in
                if lhs.cpuPercent != rhs.cpuPercent {
                    return lhs.cpuPercent > rhs.cpuPercent
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(safeMax)
            .map { $0 }
    }

    public static func runPSOutput() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "%cpu=,comm="]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = errorOutput?.isEmpty == false ? errorOutput! : "ps exited with status \(process.terminationStatus)"
            throw ProviderError.unavailable(message)
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw ProviderError.parsingFailed("Unable to decode ps output")
        }
        return output
    }
}
