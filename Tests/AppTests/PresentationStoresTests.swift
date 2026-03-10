import XCTest
@testable import PulseBarApp
import PulseBarCore

@MainActor
final class PresentationStoresTests: XCTestCase {
    func testCPUUsageSurfaceStoreAppendsAndPrunesCompactSamples() {
        let store = CPUUsageSurfaceStore()
        store.setChartSamples(user: [], system: [], window: .fifteenMinutes)

        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let recentDate = oldDate.addingTimeInterval(60)

        store.appendSamples([
            MetricSample(metricID: .cpuUserPercent, timestamp: oldDate, value: 10, unit: .percent),
            MetricSample(metricID: .cpuSystemPercent, timestamp: oldDate, value: 5, unit: .percent)
        ], at: oldDate)

        store.appendSamples([
            MetricSample(metricID: .cpuUserPercent, timestamp: recentDate, value: 15, unit: .percent),
            MetricSample(metricID: .cpuSystemPercent, timestamp: recentDate, value: 6, unit: .percent)
        ], at: recentDate)

        XCTAssertEqual(store.snapshot.renderModel.segments.count, 1)
        XCTAssertEqual(store.snapshot.renderModel.segments.first?.points.count, 2)
        XCTAssertEqual(store.snapshot.renderModel.segments.first?.points.last?.totalValue, 21)

        let muchLater = oldDate.addingTimeInterval(16 * 60)
        store.appendSamples([
            MetricSample(metricID: .cpuUserPercent, timestamp: muchLater, value: 12, unit: .percent)
        ], at: muchLater)

        XCTAssertEqual(store.snapshot.renderModel.segments.count, 1)
        XCTAssertEqual(store.snapshot.renderModel.segments.first?.points.map(\.userValue), [15])
        XCTAssertEqual(store.snapshot.renderModel.segments.first?.points.map(\.totalValue), [21])
    }

    func testCPULoadSurfaceStoreBuildsPreparedRenderModelAndScale() {
        let store = CPULoadSurfaceStore()
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let second = first.addingTimeInterval(60)
        let gap = second.addingTimeInterval(20 * 60)

        store.setChartSamples(
            load1: [
                MetricSample(metricID: .cpuLoadAverage1, timestamp: first, value: 2, unit: .scalar),
                MetricSample(metricID: .cpuLoadAverage1, timestamp: second, value: 3, unit: .scalar),
                MetricSample(metricID: .cpuLoadAverage1, timestamp: gap, value: 4, unit: .scalar)
            ],
            load5: [],
            load15: [],
            window: .oneHour
        )

        XCTAssertFalse(store.snapshot.renderModel.oneMinuteSegments.isEmpty)
        XCTAssertEqual(store.snapshot.renderModel.yDomain.lowerBound, 0)
        XCTAssertGreaterThan(store.snapshot.renderModel.yDomain.upperBound, 4)
    }

    func testCPUUsageSurfaceStoreBucketsLongWindowSamplesBeforeRendering() {
        let store = CPUUsageSurfaceStore()
        store.setChartSamples(user: [], system: [], window: .sixHours)

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        store.appendSamples([
            MetricSample(metricID: .cpuUserPercent, timestamp: start, value: 10, unit: .percent),
            MetricSample(metricID: .cpuSystemPercent, timestamp: start, value: 5, unit: .percent)
        ], at: start)

        let fiveSecondsLater = start.addingTimeInterval(5)
        store.appendSamples([
            MetricSample(metricID: .cpuUserPercent, timestamp: fiveSecondsLater, value: 20, unit: .percent),
            MetricSample(metricID: .cpuSystemPercent, timestamp: fiveSecondsLater, value: 7, unit: .percent)
        ], at: fiveSecondsLater)

        XCTAssertEqual(store.snapshot.renderModel.segments.count, 1)
        XCTAssertEqual(store.snapshot.renderModel.segments.first?.points.count, 1)
        XCTAssertEqual(store.snapshot.renderModel.segments.first?.points.first?.userValue ?? -1, 20, accuracy: 0.01)
        XCTAssertEqual(store.snapshot.renderModel.segments.first?.points.first?.totalValue ?? -1, 27, accuracy: 0.01)
    }

    func testCPUUsageSurfaceStoreUsesCompactBucketPolicyForOneHourWindow() {
        let store = CPUUsageSurfaceStore()
        store.setChartSamples(user: [], system: [], window: .oneHour)

        let start = Date(timeIntervalSince1970: 1_700_100_000)
        store.appendSamples([
            MetricSample(metricID: .cpuUserPercent, timestamp: start, value: 10, unit: .percent),
            MetricSample(metricID: .cpuSystemPercent, timestamp: start, value: 6, unit: .percent)
        ], at: start)

        let nineSecondsLater = start.addingTimeInterval(9)
        store.appendSamples([
            MetricSample(metricID: .cpuUserPercent, timestamp: nineSecondsLater, value: 18, unit: .percent),
            MetricSample(metricID: .cpuSystemPercent, timestamp: nineSecondsLater, value: 7, unit: .percent)
        ], at: nineSecondsLater)

        XCTAssertEqual(store.snapshot.renderModel.segments.first?.points.count, 1)
        XCTAssertEqual(store.snapshot.renderModel.segments.first?.points.first?.userValue ?? -1, 18, accuracy: 0.01)
        XCTAssertEqual(store.snapshot.renderModel.segments.first?.points.first?.totalValue ?? -1, 25, accuracy: 0.01)
    }

    func testTemperatureFeatureStoreBuildsSortedGroupsAndChannelMaxima() {
        let store = TemperatureFeatureStore()
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let sensors = [
            SensorReading(id: "cpu-1", rawName: "cpu-1", displayName: "CPU 1", category: .cpu, channelType: .temperatureCelsius, value: 81, source: "test", timestamp: now),
            SensorReading(id: "cpu-2", rawName: "cpu-2", displayName: "CPU 2", category: .cpu, channelType: .temperatureCelsius, value: 76, source: "test", timestamp: now),
            SensorReading(id: "fan-1", rawName: "fan-1", displayName: "Fan", category: .cpu, channelType: .fanRPM, value: 1900, source: "test", timestamp: now),
            SensorReading(id: "battery", rawName: "battery", displayName: "Battery", category: .battery, channelType: .temperatureCelsius, value: 32, source: "test", timestamp: now)
        ]

        store.update(
            visibleSensors: sensors,
            privilegedTemperatureStatusMessage: nil,
            privilegedTemperatureLastSuccessMessage: nil,
            privilegedTemperatureHealthy: true,
            privilegedSourceDiagnostics: [],
            fanParityGateBlocked: false,
            fanParityGateMessage: nil,
            temperatureHistoryStoreStatusMessage: nil
        )

        XCTAssertEqual(store.groupedSensors.map(\.category), [.battery, .cpu])
        XCTAssertEqual(store.groupedSensors.last?.channels.map(\.id), ["fan-1", "cpu-1", "cpu-2"])
        XCTAssertEqual(store.groupedSensors.last?.maxValueByChannelType[.fanRPM], 1900)
        XCTAssertEqual(store.groupedSensors.last?.maxValueByChannelType[.temperatureCelsius], 81)
    }

    func testPerformanceDiagnosticsStoreTracksRecentEventCounts() {
        let store = PerformanceDiagnosticsStore()
        let now = Date()
        store.recordCPUProcessPoll(at: now)
        store.recordMemoryProcessPoll(at: now)
        store.recordCompactChartReload(at: now)
        store.recordDetachedPaneQuery(at: now)
        store.recordFPSStatusRefresh(at: now)
        store.recordChartPreparation(milliseconds: 4.5, at: now)
        store.recordBatchHandler(milliseconds: 2.25, at: now)
        store.updateSurfaceActivitySummary("tab:CPU • fps")

        XCTAssertEqual(store.snapshot.cpuProcessPollsPerMinute, 1)
        XCTAssertEqual(store.snapshot.memoryProcessPollsPerMinute, 1)
        XCTAssertEqual(store.snapshot.compactChartReloadsPerMinute, 1)
        XCTAssertEqual(store.snapshot.detachedPaneQueriesPerMinute, 1)
        XCTAssertEqual(store.snapshot.fpsStatusRefreshesPerMinute, 1)
        XCTAssertEqual(store.snapshot.averageChartPreparationMilliseconds, 4.5)
        XCTAssertEqual(store.snapshot.averageBatchHandlerMilliseconds, 2.25)
        XCTAssertEqual(store.snapshot.surfaceActivitySummary, "tab:CPU • fps")
    }
}
