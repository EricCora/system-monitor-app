import Foundation
import PulseBarCore

@MainActor
final class TelemetryStore: ObservableObject {
    @Published var latestSamples: [MetricID: MetricSample] = [:]
    @Published var privilegedTemperatureStatusMessage: String?
    @Published var privilegedTemperatureLastSuccessMessage: String?
    @Published var privilegedTemperatureHealthy = false
    @Published var latestTemperatureSensors: [TemperatureSensorReading] = []
    @Published var latestSensorChannels: [SensorReading] = []
    @Published var latestTemperatureCapturedAt: Date?
    @Published var usingPersistedTemperatureSnapshot = false
    @Published var privilegedFanTelemetryHealthy = false
    @Published var privilegedChannelsAvailable: [SensorChannelType] = []
    @Published var privilegedActiveSourceChain: [String] = []
    @Published var privilegedSourceDiagnostics: [SensorSourceDiagnostic] = []
    @Published var fanParityGateBlocked = false
    @Published var fanParityGateMessage: String?
    @Published var temperatureHistoryStoreStatusMessage: String?
    @Published var memoryHistoryStoreStatusMessage: String?
    @Published var historyStoreStatusMessage: String?
    @Published var memoryProcessesStatusMessage: String?
    @Published var cpuProcessesStatusMessage: String?
    @Published var currentPowerSourceDescription = "Unknown"
    @Published var topMemoryProcesses: [MemoryProcessEntry] = []
    @Published var topCPUProcesses: [CPUProcessEntry] = []
    @Published var recentAlerts: [DeliveredAlert] = []
    @Published var latestGPUSummary: GPUSummarySnapshot?
    @Published var fpsStatusMessage: String?
    @Published var recentProviderFailures: [ProviderFailure] = []
    @Published var sampleRevision: UInt64 = 0
    @Published var metricHistoryRevision: UInt64 = 0
    @Published var memoryHistoryRevision: UInt64 = 0
    @Published var temperatureHistoryRevision: UInt64 = 0

    func apply(batch: SamplingBatch, recentAlerts: [DeliveredAlert]) {
        let incomingMetricIDs = Set(batch.samples.map(\.metricID))

        let includesNetworkAggregate = incomingMetricIDs.contains(.networkInBytesPerSec)
            || incomingMetricIDs.contains(.networkOutBytesPerSec)
        if includesNetworkAggregate {
            for metricID in latestSamples.keys {
                switch metricID {
                case .networkInterfaceInBytesPerSec, .networkInterfaceOutBytesPerSec:
                    if !incomingMetricIDs.contains(metricID) {
                        latestSamples[metricID] = nil
                    }
                default:
                    break
                }
            }
        }

        let includesDiskAggregate = incomingMetricIDs.contains(.diskThroughputBytesPerSec)
        let includesDiskSplit = incomingMetricIDs.contains(.diskReadBytesPerSec)
            || incomingMetricIDs.contains(.diskWriteBytesPerSec)
        if includesDiskAggregate && !includesDiskSplit {
            latestSamples[.diskReadBytesPerSec] = nil
            latestSamples[.diskWriteBytesPerSec] = nil
        }

        for sample in batch.samples {
            latestSamples[sample.metricID] = sample
        }

        if !batch.failures.isEmpty {
            recentProviderFailures = Array((batch.failures + recentProviderFailures).prefix(12))
        }

        self.recentAlerts = recentAlerts
        sampleRevision &+= 1
        if !batch.samples.isEmpty {
            metricHistoryRevision &+= 1
        }
    }

    func recordMemoryHistoryAppend() {
        memoryHistoryRevision &+= 1
    }

    func updateMemoryProcesses(_ entries: [MemoryProcessEntry], count: Int, status: String?) {
        topMemoryProcesses = Array(entries.prefix(count))
        if let status {
            memoryProcessesStatusMessage = "Process memory list unavailable: \(status)"
        } else {
            memoryProcessesStatusMessage = nil
        }
    }

    func updateCPUProcesses(_ entries: [CPUProcessEntry], count: Int, status: String?) {
        topCPUProcesses = Array(entries.prefix(count))
        if let status {
            cpuProcessesStatusMessage = "CPU process list unavailable: \(status)"
        } else {
            cpuProcessesStatusMessage = nil
        }
    }

    func setHistoryStartupStatus(
        metric: String?,
        memory: String?,
        temperature: String?
    ) {
        historyStoreStatusMessage = metric
        memoryHistoryStoreStatusMessage = memory
        temperatureHistoryStoreStatusMessage = temperature
    }

    func updateTemperatureTelemetry(
        channels: [SensorReading],
        temperatureSensors: [TemperatureSensorReading],
        statusMessage: String?,
        lastSuccessMessage: String?,
        healthy: Bool,
        fanHealthy: Bool,
        channelsAvailable: [SensorChannelType],
        activeSourceChain: [String],
        sourceDiagnostics: [SensorSourceDiagnostic],
        fanParityGateBlocked: Bool,
        fanParityGateMessage: String?,
        capturedAt: Date,
        fromPersistedSnapshot: Bool = false
    ) {
        privilegedTemperatureStatusMessage = statusMessage
        privilegedTemperatureLastSuccessMessage = lastSuccessMessage
        privilegedTemperatureHealthy = healthy
        latestSensorChannels = channels
        latestTemperatureSensors = temperatureSensors
        latestTemperatureCapturedAt = capturedAt
        usingPersistedTemperatureSnapshot = fromPersistedSnapshot
        privilegedFanTelemetryHealthy = fanHealthy
        privilegedChannelsAvailable = channelsAvailable
        privilegedActiveSourceChain = activeSourceChain
        privilegedSourceDiagnostics = sourceDiagnostics
        self.fanParityGateBlocked = fanParityGateBlocked
        self.fanParityGateMessage = fanParityGateMessage
        temperatureHistoryRevision &+= 1
    }

    func hydrateTemperatureTelemetry(
        from snapshot: LatestTemperatureSnapshot,
        statusMessage: String
    ) {
        updateTemperatureTelemetry(
            channels: snapshot.channels,
            temperatureSensors: snapshot.temperatureSensors,
            statusMessage: statusMessage,
            lastSuccessMessage: snapshot.lastSuccessMessage,
            healthy: false,
            fanHealthy: snapshot.fanHealthy,
            channelsAvailable: snapshot.channelsAvailable,
            activeSourceChain: snapshot.activeSourceChain,
            sourceDiagnostics: snapshot.sourceDiagnostics,
            fanParityGateBlocked: snapshot.fanParityGateBlocked,
            fanParityGateMessage: snapshot.fanParityGateMessage,
            capturedAt: snapshot.capturedAt,
            fromPersistedSnapshot: true
        )
    }

    func updateTemperatureTelemetryStatus(
        statusMessage: String?,
        lastSuccessMessage: String?,
        healthy: Bool
    ) {
        privilegedTemperatureStatusMessage = statusMessage
        privilegedTemperatureLastSuccessMessage = lastSuccessMessage
        privilegedTemperatureHealthy = healthy
        temperatureHistoryRevision &+= 1
    }

    func clearTemperatureTelemetry(statusMessage: String?) {
        privilegedTemperatureStatusMessage = statusMessage
        privilegedTemperatureLastSuccessMessage = nil
        privilegedTemperatureHealthy = false
        latestTemperatureSensors = []
        latestSensorChannels = []
        latestTemperatureCapturedAt = nil
        usingPersistedTemperatureSnapshot = false
        privilegedFanTelemetryHealthy = false
        privilegedChannelsAvailable = []
        privilegedActiveSourceChain = []
        privilegedSourceDiagnostics = []
        fanParityGateBlocked = false
        fanParityGateMessage = nil
        temperatureHistoryRevision &+= 1
    }

    func latestValue(for metricID: MetricID) -> MetricSample? {
        latestSamples[metricID]
    }

    func hasBatteryTelemetry() -> Bool {
        latestSamples[.batteryChargePercent] != nil || latestSamples[.batteryIsCharging] != nil
    }

    func latestCPUCores() -> [MetricSample] {
        latestSamples
            .values
            .filter {
                if case .cpuCorePercent = $0.metricID {
                    return true
                }
                return false
            }
            .sorted { lhs, rhs in
                guard case .cpuCorePercent(let l) = lhs.metricID,
                      case .cpuCorePercent(let r) = rhs.metricID else {
                    return false
                }
                return l < r
            }
    }

    func latestNetworkInterfaces() -> [NetworkInterfaceRate] {
        var inboundByInterface: [String: Double] = [:]
        var outboundByInterface: [String: Double] = [:]

        for sample in latestSamples.values {
            switch sample.metricID {
            case .networkInterfaceInBytesPerSec(let interface):
                inboundByInterface[interface] = sample.value
            case .networkInterfaceOutBytesPerSec(let interface):
                outboundByInterface[interface] = sample.value
            default:
                continue
            }
        }

        let allInterfaces = Set(inboundByInterface.keys).union(outboundByInterface.keys)
        return allInterfaces
            .map { interface in
                NetworkInterfaceRate(
                    interface: interface,
                    inboundBytesPerSecond: inboundByInterface[interface] ?? 0,
                    outboundBytesPerSecond: outboundByInterface[interface] ?? 0
                )
            }
            .sorted { lhs, rhs in
                if lhs.totalBytesPerSecond != rhs.totalBytesPerSecond {
                    return lhs.totalBytesPerSecond > rhs.totalBytesPerSecond
                }
                return lhs.interface.localizedCaseInsensitiveCompare(rhs.interface) == .orderedAscending
            }
    }

    func latestThermalState() -> ThermalStateLevel {
        let value = latestSamples[.thermalStateLevel]?.value ?? ThermalStateLevel.nominal.metricValue
        return ThermalStateLevel.from(metricValue: value)
    }

    func cpuSummarySnapshot() -> CPUSummarySnapshot {
        CPUSummarySnapshot(
            userPercent: latestSamples[.cpuUserPercent]?.value ?? 0,
            systemPercent: latestSamples[.cpuSystemPercent]?.value ?? 0,
            idlePercent: latestSamples[.cpuIdlePercent]?.value ?? 100,
            loadAverages: CPUSummarySnapshot.LoadAverageSnapshot(
                one: latestSamples[.cpuLoadAverage1]?.value ?? 0,
                five: latestSamples[.cpuLoadAverage5]?.value ?? 0,
                fifteen: latestSamples[.cpuLoadAverage15]?.value ?? 0
            ),
            framesPerSecond: latestSamples[.framesPerSecond]?.value,
            uptimeSeconds: latestSamples[.uptimeSeconds]?.value ?? ProcessInfo.processInfo.systemUptime,
            gpu: latestGPUSummary
        )
    }
}
