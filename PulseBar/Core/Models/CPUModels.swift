import Foundation

public struct CPUProcessEntry: Sendable, Equatable, Codable, Identifiable {
    public let name: String
    public let cpuPercent: Double

    public var id: String { "\(name):\(cpuPercent)" }

    public init(name: String, cpuPercent: Double) {
        self.name = name
        self.cpuPercent = cpuPercent
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
