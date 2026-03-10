import Foundation
import PulseBarCore

private let compactRenderPointLimit = 180

struct TemperatureSensorGroup: Identifiable, Equatable {
    let category: SensorCategory
    let channels: [SensorReading]
    let maxValueByChannelType: [SensorChannelType: Double]

    var id: String { category.rawValue }

    func barWidthRatio(for channel: SensorReading) -> Double {
        let maxValue = maxValueByChannelType[channel.channelType] ?? 1
        guard maxValue > 0 else { return 0 }
        return min(max(channel.value / maxValue, 0), 1)
    }
}

struct PerformanceDiagnosticsSnapshot: Equatable {
    var cpuProcessPollsPerMinute = 0
    var memoryProcessPollsPerMinute = 0
    var compactChartReloadsPerMinute = 0
    var detachedPaneQueriesPerMinute = 0
    var gpuSnapshotReadsPerMinute = 0
    var fpsStatusRefreshesPerMinute = 0
    var privilegedStatusRefreshesPerMinute = 0
    var diskFallbacksPerMinute = 0
    var chartPreparationEventsPerMinute = 0
    var averageChartPreparationMilliseconds = 0.0
    var lastChartPreparationMilliseconds = 0.0
    var averageBatchHandlerMilliseconds = 0.0
    var lastBatchHandlerMilliseconds = 0.0
    var surfaceActivitySummary = "No active surfaces"
}

struct DashboardStatusSnapshot: Equatable {
    var currentPowerSourceDescription = "Unknown"
    var privilegedTemperatureStatusMessage: String?
    var privilegedTemperatureHealthy = false
    var providerFailureCount = 0
}

@MainActor
final class PerformanceDiagnosticsStore: ObservableObject {
    @Published private(set) var snapshot = PerformanceDiagnosticsSnapshot()

    private var cpuProcessPollTimestamps: [Date] = []
    private var memoryProcessPollTimestamps: [Date] = []
    private var compactChartReloadTimestamps: [Date] = []
    private var detachedPaneQueryTimestamps: [Date] = []
    private var gpuSnapshotReadTimestamps: [Date] = []
    private var fpsStatusRefreshTimestamps: [Date] = []
    private var privilegedStatusRefreshTimestamps: [Date] = []
    private var diskFallbackTimestamps: [Date] = []
    private var chartPreparationRecords: [(timestamp: Date, milliseconds: Double)] = []
    private var batchDurationRecords: [(timestamp: Date, milliseconds: Double)] = []
    private var surfaceActivitySummary = "No active surfaces"

    func recordCPUProcessPoll(at date: Date = Date()) {
        cpuProcessPollTimestamps.append(date)
        rebuildSnapshot(now: date)
    }

    func recordMemoryProcessPoll(at date: Date = Date()) {
        memoryProcessPollTimestamps.append(date)
        rebuildSnapshot(now: date)
    }

    func recordCompactChartReload(at date: Date = Date()) {
        compactChartReloadTimestamps.append(date)
        rebuildSnapshot(now: date)
    }

    func recordDetachedPaneQuery(at date: Date = Date()) {
        detachedPaneQueryTimestamps.append(date)
        rebuildSnapshot(now: date)
    }

    func recordGPUSnapshotRead(at date: Date = Date()) {
        gpuSnapshotReadTimestamps.append(date)
        rebuildSnapshot(now: date)
    }

    func recordFPSStatusRefresh(at date: Date = Date()) {
        fpsStatusRefreshTimestamps.append(date)
        rebuildSnapshot(now: date)
    }

    func recordPrivilegedStatusRefresh(at date: Date = Date()) {
        privilegedStatusRefreshTimestamps.append(date)
        rebuildSnapshot(now: date)
    }

    func recordDiskFallback(at date: Date = Date()) {
        diskFallbackTimestamps.append(date)
        rebuildSnapshot(now: date)
    }

    func recordChartPreparation(milliseconds: Double, at date: Date = Date()) {
        chartPreparationRecords.append((date, milliseconds))
        rebuildSnapshot(now: date)
    }

    func recordBatchHandler(milliseconds: Double, at date: Date = Date()) {
        batchDurationRecords.append((date, milliseconds))
        rebuildSnapshot(now: date)
    }

    func updateSurfaceActivitySummary(_ summary: String) {
        surfaceActivitySummary = summary
        rebuildSnapshot(now: Date())
    }

    private func rebuildSnapshot(now: Date) {
        let cutoff = now.addingTimeInterval(-60)
        cpuProcessPollTimestamps.removeAll { $0 < cutoff }
        memoryProcessPollTimestamps.removeAll { $0 < cutoff }
        compactChartReloadTimestamps.removeAll { $0 < cutoff }
        detachedPaneQueryTimestamps.removeAll { $0 < cutoff }
        gpuSnapshotReadTimestamps.removeAll { $0 < cutoff }
        fpsStatusRefreshTimestamps.removeAll { $0 < cutoff }
        privilegedStatusRefreshTimestamps.removeAll { $0 < cutoff }
        diskFallbackTimestamps.removeAll { $0 < cutoff }
        chartPreparationRecords.removeAll { $0.timestamp < cutoff }
        batchDurationRecords.removeAll { $0.timestamp < cutoff }

        snapshot = PerformanceDiagnosticsSnapshot(
            cpuProcessPollsPerMinute: cpuProcessPollTimestamps.count,
            memoryProcessPollsPerMinute: memoryProcessPollTimestamps.count,
            compactChartReloadsPerMinute: compactChartReloadTimestamps.count,
            detachedPaneQueriesPerMinute: detachedPaneQueryTimestamps.count,
            gpuSnapshotReadsPerMinute: gpuSnapshotReadTimestamps.count,
            fpsStatusRefreshesPerMinute: fpsStatusRefreshTimestamps.count,
            privilegedStatusRefreshesPerMinute: privilegedStatusRefreshTimestamps.count,
            diskFallbacksPerMinute: diskFallbackTimestamps.count,
            chartPreparationEventsPerMinute: chartPreparationRecords.count,
            averageChartPreparationMilliseconds: averageMilliseconds(for: chartPreparationRecords),
            lastChartPreparationMilliseconds: chartPreparationRecords.last?.milliseconds ?? 0,
            averageBatchHandlerMilliseconds: averageMilliseconds(for: batchDurationRecords),
            lastBatchHandlerMilliseconds: batchDurationRecords.last?.milliseconds ?? 0,
            surfaceActivitySummary: surfaceActivitySummary
        )
    }

    private func averageMilliseconds(for records: [(timestamp: Date, milliseconds: Double)]) -> Double {
        guard !records.isEmpty else { return 0 }
        return records.map(\.milliseconds).reduce(0, +) / Double(records.count)
    }
}

@MainActor
final class DashboardStatusStore: ObservableObject {
    @Published private(set) var snapshot = DashboardStatusSnapshot()

    func update(
        currentPowerSourceDescription: String,
        privilegedTemperatureStatusMessage: String?,
        privilegedTemperatureHealthy: Bool,
        providerFailureCount: Int
    ) {
        let next = DashboardStatusSnapshot(
            currentPowerSourceDescription: currentPowerSourceDescription,
            privilegedTemperatureStatusMessage: privilegedTemperatureStatusMessage,
            privilegedTemperatureHealthy: privilegedTemperatureHealthy,
            providerFailureCount: providerFailureCount
        )
        guard next != snapshot else { return }
        snapshot = next
    }
}

@MainActor
struct CompactChartPoint: Equatable {
    let timestamp: Date
    let value: Double
}

struct CompactCPUUsagePoint: Equatable {
    let timestamp: Date
    let userValue: Double
    let totalValue: Double
}

struct CompactChartSegment<Point: Equatable>: Equatable {
    let points: [Point]
}

struct CompactCPUUsageRenderModel: Equatable {
    let xDomain: ClosedRange<Date>?
    let segments: [CompactChartSegment<CompactCPUUsagePoint>]

    static let empty = CompactCPUUsageRenderModel(xDomain: nil, segments: [])

    var isEmpty: Bool { segments.isEmpty }
}

struct CompactCPULoadRenderModel: Equatable {
    let xDomain: ClosedRange<Date>?
    let yDomain: ClosedRange<Double>
    let areaBaseline: Double
    let oneMinuteSegments: [CompactChartSegment<CompactChartPoint>]
    let fiveMinuteSegments: [CompactChartSegment<CompactChartPoint>]
    let fifteenMinuteSegments: [CompactChartSegment<CompactChartPoint>]

    static let empty = CompactCPULoadRenderModel(
        xDomain: nil,
        yDomain: 0...1,
        areaBaseline: 0,
        oneMinuteSegments: [],
        fiveMinuteSegments: [],
        fifteenMinuteSegments: []
    )

    var isEmpty: Bool {
        oneMinuteSegments.isEmpty && fiveMinuteSegments.isEmpty && fifteenMinuteSegments.isEmpty
    }
}

struct CPUUsageSurfaceSnapshot: Equatable {
    var summary = CPUSummarySnapshot(
        userPercent: 0,
        systemPercent: 0,
        idlePercent: 100,
        loadAverages: .init(one: 0, five: 0, fifteen: 0),
        framesPerSecond: nil,
        uptimeSeconds: ProcessInfo.processInfo.systemUptime,
        gpu: nil
    )
    var coreSamples: [MetricSample] = []
    var chartWindow: ChartWindow = .oneHour
    var renderModel = CompactCPUUsageRenderModel.empty
}

struct CPULoadSurfaceSnapshot: Equatable {
    var loadAverages = CPUSummarySnapshot.LoadAverageSnapshot(one: 0, five: 0, fifteen: 0)
    var chartWindow: ChartWindow = .oneHour
    var renderModel = CompactCPULoadRenderModel.empty
}

struct CPUProcessesSurfaceSnapshot: Equatable {
    var entries: [CPUProcessEntry] = []
    var statusMessage: String?
}

struct CPUGPUSurfaceSnapshot: Equatable {
    var summary: GPUSummarySnapshot?
}

struct CPUFPSSurfaceSnapshot: Equatable {
    var framesPerSecond: Double?
    var statusMessage: String?
}

@MainActor
final class CPUUsageSurfaceStore: ObservableObject {
    @Published private(set) var snapshot = CPUUsageSurfaceSnapshot()

    private var userSamples: [MetricSample] = []
    private var systemSamples: [MetricSample] = []

    func updateSummary(
        summary: CPUSummarySnapshot,
        coreSamples: [MetricSample]
    ) {
        var next = snapshot
        next.summary = summary
        next.coreSamples = coreSamples
        publishIfChanged(next)
    }

    func setChartWindow(_ window: ChartWindow) {
        var next = snapshot
        next.chartWindow = window
        publishIfChanged(next)
    }

    func needsHydration(for window: ChartWindow) -> Bool {
        snapshot.chartWindow != window || userSamples.isEmpty || systemSamples.isEmpty
    }

    func setChartSamples(
        user: [MetricSample],
        system: [MetricSample],
        window: ChartWindow
    ) {
        userSamples = user
        systemSamples = system

        var next = snapshot
        next.chartWindow = window
        next.renderModel = makeCPUUsageRenderModel(userSamples: userSamples, systemSamples: systemSamples)
        publishIfChanged(next)
    }

    func appendSamples(_ samples: [MetricSample], at date: Date) {
        appendLatest(metricID: .cpuUserPercent, from: samples, to: &userSamples, window: snapshot.chartWindow, now: date)
        appendLatest(metricID: .cpuSystemPercent, from: samples, to: &systemSamples, window: snapshot.chartWindow, now: date)

        var next = snapshot
        next.renderModel = makeCPUUsageRenderModel(userSamples: userSamples, systemSamples: systemSamples)
        publishIfChanged(next)
    }

    private func publishIfChanged(_ next: CPUUsageSurfaceSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}

@MainActor
final class CPULoadSurfaceStore: ObservableObject {
    @Published private(set) var snapshot = CPULoadSurfaceSnapshot()

    private var load1Samples: [MetricSample] = []
    private var load5Samples: [MetricSample] = []
    private var load15Samples: [MetricSample] = []

    func updateSummary(_ summary: CPUSummarySnapshot.LoadAverageSnapshot) {
        var next = snapshot
        next.loadAverages = summary
        publishIfChanged(next)
    }

    func needsHydration(for window: ChartWindow) -> Bool {
        snapshot.chartWindow != window || (load1Samples.isEmpty && load5Samples.isEmpty && load15Samples.isEmpty)
    }

    func setChartSamples(
        load1: [MetricSample],
        load5: [MetricSample],
        load15: [MetricSample],
        window: ChartWindow
    ) {
        load1Samples = load1
        load5Samples = load5
        load15Samples = load15

        var next = snapshot
        next.chartWindow = window
        next.renderModel = makeCPULoadRenderModel(
            oneMinuteSamples: load1Samples,
            fiveMinuteSamples: load5Samples,
            fifteenMinuteSamples: load15Samples
        )
        publishIfChanged(next)
    }

    func appendSamples(_ samples: [MetricSample], at date: Date) {
        appendLatest(metricID: .cpuLoadAverage1, from: samples, to: &load1Samples, window: snapshot.chartWindow, now: date)
        appendLatest(metricID: .cpuLoadAverage5, from: samples, to: &load5Samples, window: snapshot.chartWindow, now: date)
        appendLatest(metricID: .cpuLoadAverage15, from: samples, to: &load15Samples, window: snapshot.chartWindow, now: date)

        var next = snapshot
        next.renderModel = makeCPULoadRenderModel(
            oneMinuteSamples: load1Samples,
            fiveMinuteSamples: load5Samples,
            fifteenMinuteSamples: load15Samples
        )
        publishIfChanged(next)
    }

    private func publishIfChanged(_ next: CPULoadSurfaceSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}

@MainActor
final class CPUProcessesSurfaceStore: ObservableObject {
    @Published private(set) var snapshot = CPUProcessesSurfaceSnapshot()

    func update(entries: [CPUProcessEntry], status: String?) {
        let next = CPUProcessesSurfaceSnapshot(entries: entries, statusMessage: status)
        guard next != snapshot else { return }
        snapshot = next
    }
}

@MainActor
final class CPUGPUSurfaceStore: ObservableObject {
    @Published private(set) var snapshot = CPUGPUSurfaceSnapshot()

    func update(summary: GPUSummarySnapshot?) {
        let next = CPUGPUSurfaceSnapshot(summary: summary)
        guard next != snapshot else { return }
        snapshot = next
    }
}

@MainActor
final class CPUFPSSurfaceStore: ObservableObject {
    @Published private(set) var snapshot = CPUFPSSurfaceSnapshot()

    func update(framesPerSecond: Double?, status: String?) {
        let next = CPUFPSSurfaceSnapshot(framesPerSecond: framesPerSecond, statusMessage: status)
        guard next != snapshot else { return }
        snapshot = next
    }
}

private func makeCPUUsageRenderModel(
    userSamples: [MetricSample],
    systemSamples: [MetricSample]
) -> CompactCPUUsageRenderModel {
    let sanitizedUser = ChartSeriesPipeline.sanitize(userSamples, timestamp: \.timestamp)
    let sanitizedSystem = ChartSeriesPipeline.sanitize(systemSamples, timestamp: \.timestamp)
    guard !sanitizedUser.isEmpty, !sanitizedSystem.isEmpty else { return .empty }

    let userByTimestamp = Dictionary(uniqueKeysWithValues: sanitizedUser.map { ($0.timestamp, $0) })
    let systemByTimestamp = Dictionary(uniqueKeysWithValues: sanitizedSystem.map { ($0.timestamp, $0) })
    let timestamps = userByTimestamp.keys
        .filter { systemByTimestamp[$0] != nil }
        .sorted()

    guard !timestamps.isEmpty else { return .empty }

    let points = timestamps.compactMap { timestamp -> CompactCPUUsagePoint? in
        guard let user = userByTimestamp[timestamp], let system = systemByTimestamp[timestamp] else { return nil }
        return CompactCPUUsagePoint(
            timestamp: timestamp,
            userValue: user.value,
            totalValue: user.value + system.value
        )
    }
    let preparedPoints = downsampleUsagePoints(points, maxPoints: compactRenderPointLimit)
    guard !preparedPoints.isEmpty else { return .empty }

    let keys = ChartSeriesPipeline.continuityKeys(for: preparedPoints, seriesKey: "cpu.usage", timestamp: \.timestamp)
    let segments = Dictionary(grouping: zip(preparedPoints, keys), by: \.1)
        .values
        .map { values in
            CompactChartSegment(points: values.map(\.0).sorted { $0.timestamp < $1.timestamp })
        }
        .sorted {
            guard let lhs = $0.points.first?.timestamp, let rhs = $1.points.first?.timestamp else { return false }
            return lhs < rhs
        }

    return CompactCPUUsageRenderModel(
        xDomain: xDomain(for: preparedPoints.map(\.timestamp)),
        segments: segments
    )
}

private func makeCPULoadRenderModel(
    oneMinuteSamples: [MetricSample],
    fiveMinuteSamples: [MetricSample],
    fifteenMinuteSamples: [MetricSample]
) -> CompactCPULoadRenderModel {
    let oneSegments = makeChartSegments(from: oneMinuteSamples, seriesKey: "cpu.load.1")
    let fiveSegments = makeChartSegments(from: fiveMinuteSamples, seriesKey: "cpu.load.5")
    let fifteenSegments = makeChartSegments(from: fifteenMinuteSamples, seriesKey: "cpu.load.15")

    let allPoints = (oneSegments + fiveSegments + fifteenSegments).flatMap(\.points)
    guard !allPoints.isEmpty else { return .empty }

    let values = allPoints.map(\.value)
    let upperBound = max(values.max() ?? 1, 1)
    let span = max(upperBound, 1)
    let padding = span * 0.12

    return CompactCPULoadRenderModel(
        xDomain: xDomain(for: allPoints.map(\.timestamp)),
        yDomain: 0...(upperBound + padding),
        areaBaseline: 0,
        oneMinuteSegments: oneSegments,
        fiveMinuteSegments: fiveSegments,
        fifteenMinuteSegments: fifteenSegments
    )
}

private func makeChartSegments(
    from samples: [MetricSample],
    seriesKey: String
) -> [CompactChartSegment<CompactChartPoint>] {
    let sanitized = downsampleCompactSamples(
        ChartSeriesPipeline.sanitize(samples, timestamp: \.timestamp),
        maxPoints: compactRenderPointLimit
    )
    guard !sanitized.isEmpty else { return [] }

    let keys = ChartSeriesPipeline.continuityKeys(for: sanitized, seriesKey: seriesKey, timestamp: \.timestamp)
    return Dictionary(grouping: zip(sanitized, keys), by: \.1)
        .values
        .map { values in
            CompactChartSegment(
                points: values
                    .map { CompactChartPoint(timestamp: $0.0.timestamp, value: $0.0.value) }
                    .sorted { $0.timestamp < $1.timestamp }
            )
        }
        .sorted {
            guard let lhs = $0.points.first?.timestamp, let rhs = $1.points.first?.timestamp else { return false }
            return lhs < rhs
        }
}

private func xDomain(for timestamps: [Date]) -> ClosedRange<Date>? {
    guard let first = timestamps.min(), let last = timestamps.max() else { return nil }
    return first...last
}

private func downsampleCompactSamples(_ samples: [MetricSample], maxPoints: Int) -> [MetricSample] {
    Downsampler.downsample(samples, maxPoints: maxPoints)
}

private func downsampleUsagePoints(_ points: [CompactCPUUsagePoint], maxPoints: Int) -> [CompactCPUUsagePoint] {
    guard maxPoints > 0, points.count > maxPoints else {
        return points
    }

    let bucketSize = Int(ceil(Double(points.count) / Double(maxPoints)))
    var output: [CompactCPUUsagePoint] = []
    output.reserveCapacity(maxPoints)

    var index = 0
    while index < points.count {
        let end = min(index + bucketSize, points.count)
        let bucket = points[index..<end]
        guard let last = bucket.last else {
            index = end
            continue
        }

        let userAverage = bucket.reduce(0.0) { $0 + $1.userValue } / Double(bucket.count)
        let totalAverage = bucket.reduce(0.0) { $0 + $1.totalValue } / Double(bucket.count)
        output.append(
            CompactCPUUsagePoint(
                timestamp: last.timestamp,
                userValue: userAverage,
                totalValue: totalAverage
            )
        )
        index = end
    }

    return output
}

@MainActor
final class MemoryFeatureStore: ObservableObject {
    @Published private(set) var pressurePercent = 0.0
    @Published private(set) var wiredBytes = 0.0
    @Published private(set) var activeBytes = 0.0
    @Published private(set) var compressedBytes = 0.0
    @Published private(set) var freeBytes = 0.0
    @Published private(set) var appBytes = 0.0
    @Published private(set) var cacheBytes = 0.0
    @Published private(set) var swapUsedBytes = 0.0
    @Published private(set) var swapTotalBytes = 0.0
    @Published private(set) var pageInsBytesPerSecond = 0.0
    @Published private(set) var pageOutsBytesPerSecond = 0.0
    @Published private(set) var topProcesses: [MemoryProcessEntry] = []
    @Published private(set) var processesStatusMessage: String?

    func updateMetrics(from latestSamples: [MetricID: MetricSample]) {
        pressurePercent = latestSamples[.memoryPressureLevel]?.value ?? 0
        wiredBytes = latestSamples[.memoryWiredBytes]?.value ?? 0
        activeBytes = latestSamples[.memoryActiveBytes]?.value ?? 0
        compressedBytes = latestSamples[.memoryCompressedBytes]?.value ?? 0
        freeBytes = latestSamples[.memoryFreeBytes]?.value ?? 0
        appBytes = latestSamples[.memoryAppBytes]?.value ?? 0
        cacheBytes = latestSamples[.memoryCacheBytes]?.value ?? 0
        swapUsedBytes = latestSamples[.memorySwapUsedBytes]?.value ?? 0
        swapTotalBytes = max(swapUsedBytes, latestSamples[.memorySwapTotalBytes]?.value ?? 0)
        pageInsBytesPerSecond = latestSamples[.memoryPageInsBytesPerSec]?.value ?? 0
        pageOutsBytesPerSecond = latestSamples[.memoryPageOutsBytesPerSec]?.value ?? 0
    }

    func updateProcesses(entries: [MemoryProcessEntry], status: String?) {
        topProcesses = entries
        processesStatusMessage = status
    }
}

@MainActor
final class BatteryFeatureStore: ObservableObject {
    @Published private(set) var chargePercent = 0.0
    @Published private(set) var isCharging = false
    @Published private(set) var currentMilliamps: Double?
    @Published private(set) var powerWatts: Double?
    @Published private(set) var timeRemainingMinutes: Double?
    @Published private(set) var healthPercent: Double?
    @Published private(set) var cycleCount: Double?
    @Published private(set) var chargeSamples: [MetricSample] = []
    @Published private(set) var powerSamples: [MetricSample] = []
    @Published private(set) var chartWindow: ChartWindow = .oneHour

    func updateMetrics(from latestSamples: [MetricID: MetricSample]) {
        chargePercent = latestSamples[.batteryChargePercent]?.value ?? 0
        isCharging = (latestSamples[.batteryIsCharging]?.value ?? 0) >= 0.5
        currentMilliamps = latestSamples[.batteryCurrentMilliAmps]?.value
        powerWatts = latestSamples[.batteryPowerWatts]?.value
        timeRemainingMinutes = latestSamples[.batteryTimeRemainingMinutes]?.value
        healthPercent = latestSamples[.batteryHealthPercent]?.value
        cycleCount = latestSamples[.batteryCycleCount]?.value
    }

    func setChartWindow(_ window: ChartWindow) {
        chartWindow = window
    }

    func setChartSamples(charge: [MetricSample], power: [MetricSample], window: ChartWindow) {
        chargeSamples = charge
        powerSamples = power
        chartWindow = window
    }

    func appendCompactSamples(_ samples: [MetricSample], at date: Date) {
        appendLatest(metricID: .batteryChargePercent, from: samples, to: &chargeSamples, window: chartWindow, now: date)
        appendLatest(metricID: .batteryPowerWatts, from: samples, to: &powerSamples, window: chartWindow, now: date)
    }
}

@MainActor
final class NetworkFeatureStore: ObservableObject {
    @Published private(set) var inboundBytesPerSecond = 0.0
    @Published private(set) var outboundBytesPerSecond = 0.0
    @Published private(set) var interfaceRates: [NetworkInterfaceRate] = []
    @Published private(set) var inboundSamples: [MetricSample] = []
    @Published private(set) var outboundSamples: [MetricSample] = []
    @Published private(set) var chartWindow: ChartWindow = .oneHour

    func updateMetrics(from latestSamples: [MetricID: MetricSample], interfaceRates: [NetworkInterfaceRate]) {
        inboundBytesPerSecond = latestSamples[.networkInBytesPerSec]?.value ?? 0
        outboundBytesPerSecond = latestSamples[.networkOutBytesPerSec]?.value ?? 0
        self.interfaceRates = interfaceRates
    }

    func setChartWindow(_ window: ChartWindow) {
        chartWindow = window
    }

    func setChartSamples(inbound: [MetricSample], outbound: [MetricSample], window: ChartWindow) {
        inboundSamples = inbound
        outboundSamples = outbound
        chartWindow = window
    }

    func appendCompactSamples(_ samples: [MetricSample], at date: Date) {
        appendLatest(metricID: .networkInBytesPerSec, from: samples, to: &inboundSamples, window: chartWindow, now: date)
        appendLatest(metricID: .networkOutBytesPerSec, from: samples, to: &outboundSamples, window: chartWindow, now: date)
    }
}

@MainActor
final class DiskFeatureStore: ObservableObject {
    @Published private(set) var readBytesPerSecond = 0.0
    @Published private(set) var writeBytesPerSecond = 0.0
    @Published private(set) var combinedBytesPerSecond = 0.0
    @Published private(set) var freeBytes = 0.0
    @Published private(set) var smartStatusCode: Double?
    @Published private(set) var readSamples: [MetricSample] = []
    @Published private(set) var writeSamples: [MetricSample] = []
    @Published private(set) var throughputSamples: [MetricSample] = []
    @Published private(set) var chartWindow: ChartWindow = .oneHour

    func updateMetrics(from latestSamples: [MetricID: MetricSample]) {
        readBytesPerSecond = latestSamples[.diskReadBytesPerSec]?.value ?? 0
        writeBytesPerSecond = latestSamples[.diskWriteBytesPerSec]?.value ?? 0
        combinedBytesPerSecond = latestSamples[.diskThroughputBytesPerSec]?.value ?? 0
        freeBytes = latestSamples[.diskFreeBytes]?.value ?? 0
        smartStatusCode = latestSamples[.diskSMARTStatusCode]?.value
    }

    func setChartWindow(_ window: ChartWindow) {
        chartWindow = window
    }

    func setChartSamples(read: [MetricSample], write: [MetricSample], throughput: [MetricSample], window: ChartWindow) {
        readSamples = read
        writeSamples = write
        throughputSamples = throughput
        chartWindow = window
    }

    func appendCompactSamples(_ samples: [MetricSample], at date: Date) {
        appendLatest(metricID: .diskReadBytesPerSec, from: samples, to: &readSamples, window: chartWindow, now: date)
        appendLatest(metricID: .diskWriteBytesPerSec, from: samples, to: &writeSamples, window: chartWindow, now: date)
        appendLatest(metricID: .diskThroughputBytesPerSec, from: samples, to: &throughputSamples, window: chartWindow, now: date)
    }
}

@MainActor
final class TemperatureFeatureStore: ObservableObject {
    @Published private(set) var visibleSensors: [SensorReading] = []
    @Published private(set) var groupedSensors: [TemperatureSensorGroup] = []
    @Published private(set) var privilegedTemperatureStatusMessage: String?
    @Published private(set) var privilegedTemperatureLastSuccessMessage: String?
    @Published private(set) var privilegedTemperatureHealthy = false
    @Published private(set) var privilegedSourceDiagnostics: [SensorSourceDiagnostic] = []
    @Published private(set) var fanParityGateBlocked = false
    @Published private(set) var fanParityGateMessage: String?
    @Published private(set) var temperatureHistoryStoreStatusMessage: String?

    func update(
        visibleSensors: [SensorReading],
        privilegedTemperatureStatusMessage: String?,
        privilegedTemperatureLastSuccessMessage: String?,
        privilegedTemperatureHealthy: Bool,
        privilegedSourceDiagnostics: [SensorSourceDiagnostic],
        fanParityGateBlocked: Bool,
        fanParityGateMessage: String?,
        temperatureHistoryStoreStatusMessage: String?
    ) {
        self.visibleSensors = visibleSensors
        groupedSensors = Self.makeGroups(from: visibleSensors)
        self.privilegedTemperatureStatusMessage = privilegedTemperatureStatusMessage
        self.privilegedTemperatureLastSuccessMessage = privilegedTemperatureLastSuccessMessage
        self.privilegedTemperatureHealthy = privilegedTemperatureHealthy
        self.privilegedSourceDiagnostics = privilegedSourceDiagnostics
        self.fanParityGateBlocked = fanParityGateBlocked
        self.fanParityGateMessage = fanParityGateMessage
        self.temperatureHistoryStoreStatusMessage = temperatureHistoryStoreStatusMessage
    }

    private static func makeGroups(from visibleSensors: [SensorReading]) -> [TemperatureSensorGroup] {
        Dictionary(grouping: visibleSensors, by: \.category)
            .map { category, channels in
                let sortedChannels = channels.sorted { lhs, rhs in
                    if lhs.channelType != rhs.channelType {
                        return lhs.channelType.rawValue < rhs.channelType.rawValue
                    }
                    if lhs.value != rhs.value {
                        return lhs.value > rhs.value
                    }
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }

                var maxima: [SensorChannelType: Double] = [:]
                for channelType in SensorChannelType.allCases {
                    let values = sortedChannels
                        .filter { $0.channelType == channelType }
                        .map(\.value)
                    switch channelType {
                    case .temperatureCelsius:
                        maxima[channelType] = max(50, values.max() ?? 50)
                    case .fanRPM:
                        maxima[channelType] = max(1000, values.max() ?? 1000)
                    }
                }

                return TemperatureSensorGroup(
                    category: category,
                    channels: sortedChannels,
                    maxValueByChannelType: maxima
                )
            }
            .sorted { $0.category.label < $1.category.label }
    }
}

private func appendLatest(
    metricID: MetricID,
    from samples: [MetricSample],
    to series: inout [MetricSample],
    window: ChartWindow,
    now: Date
) {
    guard let sample = samples.last(where: { $0.metricID == metricID }) else {
        series.removeAll { now.timeIntervalSince($0.timestamp) > window.seconds }
        return
    }

    let preparedSample = bucketedSample(sample, bucketSeconds: compactBucketSeconds(for: window))

    if let last = series.last, last.timestamp == preparedSample.timestamp {
        series[series.count - 1] = preparedSample
    } else {
        series.append(preparedSample)
    }

    let cutoff = now.addingTimeInterval(-window.seconds)
    series.removeAll { $0.timestamp < cutoff }
}

private func bucketedSample(_ sample: MetricSample, bucketSeconds: Int) -> MetricSample {
    guard bucketSeconds > 1 else { return sample }
    let bucket = TimeInterval(bucketSeconds)
    let timestamp = sample.timestamp.timeIntervalSince1970
    let bucketedTimestamp = floor(timestamp / bucket) * bucket
    return MetricSample(
        metricID: sample.metricID,
        timestamp: Date(timeIntervalSince1970: bucketedTimestamp),
        value: sample.value,
        unit: sample.unit
    )
}

private func compactBucketSeconds(for window: ChartWindow) -> Int {
    switch window {
    case .fifteenMinutes:
        return 5
    case .oneHour:
        return 10
    case .sixHours:
        return 60
    case .oneDay:
        return 300
    case .oneWeek:
        return 1_800
    case .oneMonth:
        return 7_200
    }
}

func durationMilliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1_000
        + Double(duration.components.attoseconds) / 1_000_000_000_000_000
}
