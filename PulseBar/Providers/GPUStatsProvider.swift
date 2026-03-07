import Foundation
import IOKit

public actor GPUStatsProvider: MetricProvider {
    public nonisolated let providerID = "gpu"
    public typealias SnapshotReader = @Sendable () -> GPUSummarySnapshot

    private let snapshotReader: SnapshotReader
    private var lastSnapshot: GPUSummarySnapshot

    public init() {
        self.snapshotReader = { GPUStatsProvider.readSnapshot() }
        self.lastSnapshot = self.snapshotReader()
    }

    public init(snapshotReader: @escaping SnapshotReader) {
        self.snapshotReader = snapshotReader
        self.lastSnapshot = snapshotReader()
    }

    public func currentSnapshot() -> GPUSummarySnapshot {
        let snapshot = snapshotReader()
        lastSnapshot = snapshot
        return snapshot
    }

    public func latestSnapshot() -> GPUSummarySnapshot {
        lastSnapshot
    }

    public func sample(at date: Date) async throws -> [MetricSample] {
        let snapshot = currentSnapshot()
        var samples: [MetricSample] = []

        if let processorPercent = snapshot.processorPercent {
            samples.append(
                MetricSample(
                    metricID: .gpuProcessorPercent,
                    timestamp: date,
                    value: processorPercent,
                    unit: .percent
                )
            )
        }

        if let memoryPercent = snapshot.memoryPercent {
            samples.append(
                MetricSample(
                    metricID: .gpuMemoryPercent,
                    timestamp: date,
                    value: memoryPercent,
                    unit: .percent
                )
            )
        }

        return samples
    }

    static func readSnapshot() -> GPUSummarySnapshot {
        let matching = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return unavailableSnapshot(deviceName: "Apple Silicon")
        }
        defer { IOObjectRelease(iterator) }

        var unavailableCandidate: GPUSummarySnapshot?

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            guard let properties = copyProperties(for: service) else {
                continue
            }

            let snapshot = snapshot(from: properties)
            if snapshot.available {
                return snapshot
            }

            if unavailableCandidate == nil {
                unavailableCandidate = snapshot
            }
        }

        return unavailableCandidate ?? unavailableSnapshot(deviceName: primaryGPUName() ?? "Apple Silicon")
    }

    static func snapshot(from properties: [String: Any]) -> GPUSummarySnapshot {
        let deviceName = decodeDeviceName(from: properties) ?? "Apple Silicon"
        let performance = performanceStatistics(from: properties)

        let rendererUtilization = numericValue(in: performance, keys: ["Renderer Utilization %"])
        let tilerUtilization = numericValue(in: performance, keys: ["Tiler Utilization %"])
        let processorPercent = (
            numericValue(in: performance, keys: ["Device Utilization %", "GPU Utilization %"])
            ?? max(rendererUtilization ?? 0, tilerUtilization ?? 0)
        )?
        .clamped(to: 0...100)

        let inUseMemoryBytes = numericValue(
            in: performance,
            keys: [
                "In use system memory",
                "In use video memory",
                "In use memory"
            ]
        )

        let allocatedMemoryBytes = numericValue(
            in: performance,
            keys: [
                "Alloc system memory",
                "Alloc video memory",
                "Alloc memory",
                "Recommended Max Working Set Size"
            ]
        )

        let memoryPercent: Double?
        if let inUseMemoryBytes, let allocatedMemoryBytes, allocatedMemoryBytes > 0 {
            memoryPercent = (inUseMemoryBytes / allocatedMemoryBytes * 100).clamped(to: 0...100)
        } else {
            memoryPercent = nil
        }

        let available = processorPercent != nil || memoryPercent != nil
        return GPUSummarySnapshot(
            processorPercent: processorPercent,
            memoryPercent: memoryPercent,
            deviceName: deviceName,
            available: available,
            statusMessage: available
                ? nil
                : "Live GPU processor and memory telemetry is unavailable from IOAccelerator on this Mac."
        )
    }

    private static func unavailableSnapshot(deviceName: String) -> GPUSummarySnapshot {
        GPUSummarySnapshot(
            processorPercent: nil,
            memoryPercent: nil,
            deviceName: deviceName,
            available: false,
            statusMessage: "Live GPU processor and memory telemetry is unavailable from IOAccelerator on this Mac."
        )
    }

    private static func copyProperties(for service: io_registry_entry_t) -> [String: Any]? {
        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        )
        guard result == KERN_SUCCESS,
              let properties = unmanagedProperties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return properties
    }

    private static func performanceStatistics(from properties: [String: Any]) -> [String: Any] {
        if let dictionary = properties["PerformanceStatistics"] as? [String: Any] {
            return dictionary
        }

        if let dictionary = properties["PerformanceStatistics"] as? NSDictionary {
            return dictionary as? [String: Any] ?? [:]
        }

        return [:]
    }

    private static func decodeDeviceName(from properties: [String: Any]) -> String? {
        if let model = properties["model"] {
            return normalizedString(from: model)
        }

        if let ioClass = properties["IOClass"] as? String, !ioClass.isEmpty {
            return ioClass
        }

        return nil
    }

    private static func primaryGPUName() -> String? {
        let matching = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let properties = copyProperties(for: service),
                  let name = decodeDeviceName(from: properties),
                  !name.isEmpty else {
                continue
            }
            return name
        }

        return nil
    }

    private static func numericValue(in dictionary: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            guard let rawValue = dictionary[key] else {
                continue
            }

            if let number = rawValue as? NSNumber {
                return number.doubleValue
            }

            if let doubleValue = rawValue as? Double {
                return doubleValue
            }

            if let intValue = rawValue as? Int {
                return Double(intValue)
            }

            if let stringValue = rawValue as? String,
               let doubleValue = Double(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return doubleValue
            }
        }

        return nil
    }

    private static func normalizedString(from value: Any) -> String? {
        if let data = value as? Data,
           let decoded = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines)),
           !decoded.isEmpty {
            return decoded
        }

        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
            return trimmed.isEmpty ? nil : trimmed
        }

        return nil
    }
}
