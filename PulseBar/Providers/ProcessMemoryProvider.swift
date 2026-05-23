import Foundation

public struct MemoryProcessEntry: Sendable, Equatable, Codable, Identifiable {
    public let pid: Int32
    /// `ps` command column (legacy persisted field).
    public let name: String
    public let executablePath: String
    public let displayName: String
    public let residentBytes: Double

    public var id: String {
        pid > 0 ? "pid:\(pid)" : "legacy:\(name):\(Int(residentBytes.rounded()))"
    }

    public init(
        pid: Int32 = 0,
        name: String,
        executablePath: String? = nil,
        displayName: String? = nil,
        residentBytes: Double
    ) {
        self.pid = pid
        self.name = name
        self.residentBytes = residentBytes
        let resolvedPath = executablePath ?? (name.hasPrefix("/") ? name : "")
        self.executablePath = resolvedPath.isEmpty ? name : resolvedPath
        self.displayName = displayName ?? ProcessDisplayNameFormatter.format(
            executablePath: self.executablePath,
            fallback: name
        )
    }

    private enum CodingKeys: String, CodingKey {
        case pid
        case name
        case executablePath
        case displayName
        case residentBytes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        residentBytes = try container.decode(Double.self, forKey: .residentBytes)
        pid = try container.decodeIfPresent(Int32.self, forKey: .pid) ?? 0
        let decodedPath = try container.decodeIfPresent(String.self, forKey: .executablePath)
        executablePath = decodedPath ?? (name.hasPrefix("/") ? name : "")
        if let decodedDisplayName = try container.decodeIfPresent(String.self, forKey: .displayName),
           !decodedDisplayName.isEmpty {
            displayName = decodedDisplayName
        } else {
            displayName = ProcessDisplayNameFormatter.format(
                executablePath: executablePath.isEmpty ? name : executablePath,
                fallback: name
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pid, forKey: .pid)
        try container.encode(name, forKey: .name)
        try container.encode(executablePath, forKey: .executablePath)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(residentBytes, forKey: .residentBytes)
    }
}

public actor ProcessMemoryProvider {
    public typealias ProcessRunner = @Sendable () throws -> String

    private let maxEntries: Int
    private let processRunner: ProcessRunner
    private var minCollectionInterval: TimeInterval

    private var cachedSnapshot: (timestamp: Date, entries: [MemoryProcessEntry])?
    private var lastErrorMessage: String?

    public init(
        maxEntries: Int = 5,
        minCollectionInterval: TimeInterval = 5,
        processRunner: @escaping ProcessRunner = ProcessListProviderSupport.memoryProcessOutput
    ) {
        self.maxEntries = max(1, maxEntries)
        self.minCollectionInterval = max(1, minCollectionInterval)
        self.processRunner = processRunner
    }

    public func topProcesses(at date: Date = Date()) async -> [MemoryProcessEntry] {
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

    static func parsePSOutput(_ output: String, maxEntries: Int) -> [MemoryProcessEntry] {
        let safeMax = max(1, maxEntries)
        let lines = output.split(whereSeparator: \.isNewline)
        var entries: [MemoryProcessEntry] = []
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
                if lhs.residentBytes != rhs.residentBytes {
                    return lhs.residentBytes > rhs.residentBytes
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            .prefix(safeMax)
            .map { $0 }
    }

    private static func parseLine(_ trimmed: String) -> MemoryProcessEntry? {
        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count >= 3,
              let pid = Int32(tokens[0]),
              let rssKilobytes = Double(tokens[1]),
              rssKilobytes >= 0 else {
            return parseLegacyLine(trimmed)
        }

        let comm = tokens.dropFirst(2).joined(separator: " ")
        guard !comm.isEmpty else { return nil }

        let executablePath = ProcessExecutablePathResolver.executablePath(pid: pid, comm: comm)
        let displayName = ProcessDisplayNameFormatter.format(executablePath: executablePath, fallback: comm)
        return MemoryProcessEntry(
            pid: pid,
            name: comm,
            executablePath: executablePath,
            displayName: displayName,
            residentBytes: rssKilobytes * 1024.0
        )
    }

    private static func parseLegacyLine(_ trimmed: String) -> MemoryProcessEntry? {
        guard let rssStart = trimmed.firstIndex(where: { !$0.isWhitespace }) else {
            return nil
        }
        guard let splitIndex = trimmed[rssStart...].firstIndex(where: \.isWhitespace) else {
            return nil
        }

        let rssToken = String(trimmed[rssStart..<splitIndex])
        guard let rssKilobytes = Double(rssToken), rssKilobytes >= 0 else {
            return nil
        }

        let nameToken = trimmed[splitIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nameToken.isEmpty else { return nil }

        return MemoryProcessEntry(
            pid: 0,
            name: nameToken,
            executablePath: nameToken,
            displayName: ProcessDisplayNameFormatter.format(executablePath: nameToken, fallback: nameToken),
            residentBytes: rssKilobytes * 1024.0
        )
    }

}
