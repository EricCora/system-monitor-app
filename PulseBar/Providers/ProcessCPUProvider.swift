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
        processRunner: @escaping ProcessRunner = ProcessListProviderSupport.cpuProcessOutput
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

            guard let entry = parseLine(trimmed) else {
                continue
            }
            entries.append(entry)
        }

        return entries
            .sorted { lhs, rhs in
                if lhs.cpuPercent != rhs.cpuPercent {
                    return lhs.cpuPercent > rhs.cpuPercent
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            .prefix(safeMax)
            .map { $0 }
    }

    private static func parseLine(_ trimmed: String) -> CPUProcessEntry? {
        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count >= 3,
              let pid = Int32(tokens[0]),
              let cpuPercent = Double(tokens[1].replacingOccurrences(of: ",", with: ".")),
              cpuPercent >= 0 else {
            return parseLegacyLine(trimmed)
        }

        let comm = tokens.dropFirst(2).joined(separator: " ")
        guard !comm.isEmpty else { return nil }

        let executablePath = ProcessExecutablePathResolver.executablePath(pid: pid, comm: comm)
        let displayName = ProcessDisplayNameFormatter.format(executablePath: executablePath, fallback: comm)
        return CPUProcessEntry(
            pid: pid,
            name: comm,
            executablePath: executablePath,
            displayName: displayName,
            cpuPercent: cpuPercent
        )
    }

    private static func parseLegacyLine(_ trimmed: String) -> CPUProcessEntry? {
        guard let parsed = ProcessListProviderSupport.parseLegacyCPULine(trimmed) else {
            return nil
        }
        return CPUProcessEntry(
            pid: 0,
            name: parsed.name,
            executablePath: parsed.name,
            displayName: ProcessDisplayNameFormatter.format(executablePath: parsed.name, fallback: parsed.name),
            cpuPercent: parsed.value
        )
    }
}
