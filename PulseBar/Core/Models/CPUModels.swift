import Foundation

public struct CPUProcessEntry: Sendable, Equatable, Codable, Identifiable {
    public let pid: Int32
    public let name: String
    public let executablePath: String
    public let displayName: String
    public let cpuPercent: Double

    public var id: String {
        pid > 0 ? "pid:\(pid)" : "legacy:\(name):\(cpuPercent)"
    }

    public init(
        pid: Int32,
        name: String,
        executablePath: String,
        displayName: String,
        cpuPercent: Double
    ) {
        self.pid = pid
        self.name = name
        self.executablePath = executablePath
        self.displayName = displayName
        self.cpuPercent = cpuPercent
    }

    /// Legacy convenience for tests and decoded snapshots that only stored `name` + `cpuPercent`.
    public init(name: String, cpuPercent: Double) {
        self.init(
            pid: 0,
            name: name,
            executablePath: name,
            displayName: ProcessDisplayNameFormatter.format(executablePath: name, fallback: name),
            cpuPercent: cpuPercent
        )
    }

    private enum CodingKeys: String, CodingKey {
        case pid
        case name
        case executablePath
        case displayName
        case cpuPercent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        cpuPercent = try container.decode(Double.self, forKey: .cpuPercent)
        pid = try container.decodeIfPresent(Int32.self, forKey: .pid) ?? 0
        executablePath = try container.decodeIfPresent(String.self, forKey: .executablePath) ?? name
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
        try container.encode(cpuPercent, forKey: .cpuPercent)
    }
}

public struct GPUSummarySnapshot: Sendable, Equatable, Codable {
    public let processorPercent: Double?
    public let memoryPercent: Double?
    public let deviceName: String
    public let available: Bool
    public let statusMessage: String?

    public init(
        processorPercent: Double?,
        memoryPercent: Double?,
        deviceName: String,
        available: Bool,
        statusMessage: String? = nil
    ) {
        self.processorPercent = processorPercent
        self.memoryPercent = memoryPercent
        self.deviceName = deviceName
        self.available = available
        self.statusMessage = statusMessage
    }
}

public struct CPUSummarySnapshot: Sendable, Equatable, Codable {
    public struct LoadAverageSnapshot: Sendable, Equatable, Codable {
        public let one: Double
        public let five: Double
        public let fifteen: Double

        public init(one: Double, five: Double, fifteen: Double) {
            self.one = one
            self.five = five
            self.fifteen = fifteen
        }
    }

    public let userPercent: Double
    public let systemPercent: Double
    public let idlePercent: Double
    public let loadAverages: LoadAverageSnapshot
    public let framesPerSecond: Double?
    public let uptimeSeconds: Double
    public let gpu: GPUSummarySnapshot?

    public init(
        userPercent: Double,
        systemPercent: Double,
        idlePercent: Double,
        loadAverages: LoadAverageSnapshot,
        framesPerSecond: Double?,
        uptimeSeconds: Double,
        gpu: GPUSummarySnapshot?
    ) {
        self.userPercent = userPercent
        self.systemPercent = systemPercent
        self.idlePercent = idlePercent
        self.loadAverages = loadAverages
        self.framesPerSecond = framesPerSecond
        self.uptimeSeconds = uptimeSeconds
        self.gpu = gpu
    }
}
