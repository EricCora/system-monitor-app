import XCTest
@testable import PulseBarApp
import PulseBarCore

@MainActor
final class PresentationStoresTests: XCTestCase {
    func testSensorDisplayMapperKeepsMonitorSensorSuffixesAndClassifiesISPWithSoC() {
        let now = Date(timeIntervalSince1970: 1_700_000_050)
        let gpu = SensorDisplayNameMapper.present(
            SensorReading(
                id: "gpu",
                rawName: "GPU MTR Temp Sensor4",
                displayName: "GPU MTR Temp Sensor4",
                category: .other,
                channelType: .temperatureCelsius,
                value: 47,
                source: "test",
                timestamp: now
            )
        )
        let isp = SensorDisplayNameMapper.present(
            SensorReading(
                id: "isp",
                rawName: "ISP MTR Temp Sensor5",
                displayName: "ISP MTR Temp Sensor5",
                category: .other,
                channelType: .temperatureCelsius,
                value: 42,
                source: "test",
                timestamp: now
            )
        )

        XCTAssertEqual(gpu.displayName, "GPU Sensor 4")
        XCTAssertEqual(gpu.category, .gpu)
        XCTAssertEqual(isp.displayName, "Image Signal Processor Sensor 5")
        XCTAssertEqual(isp.category, .soc)
    }

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

    func testNetworkFeatureStoreFiltersImpossibleThroughputSpikesFromChartsAndReadouts() {
        let store = NetworkFeatureStore()
        let now = Date(timeIntervalSince1970: 1_700_100_000)
        let impossible = NetworkFeatureStore.maximumPlausibleThroughputBytesPerSecond * 10

        store.updateMetrics(
            from: [
                .networkInBytesPerSec: MetricSample(metricID: .networkInBytesPerSec, timestamp: now, value: impossible, unit: .bytesPerSecond),
                .networkOutBytesPerSec: MetricSample(metricID: .networkOutBytesPerSec, timestamp: now, value: 1_024, unit: .bytesPerSecond)
            ],
            interfaceRates: [
                NetworkInterfaceRate(interface: "en0", inboundBytesPerSecond: impossible, outboundBytesPerSecond: 2_048)
            ]
        )

        XCTAssertEqual(store.inboundBytesPerSecond, 0)
        XCTAssertEqual(store.outboundBytesPerSecond, 1_024)
        XCTAssertEqual(store.interfaceRates.first?.inboundBytesPerSecond, 0)
        XCTAssertEqual(store.interfaceRates.first?.outboundBytesPerSecond, 2_048)

        store.setChartSamples(
            inbound: [
                MetricSample(metricID: .networkInBytesPerSec, timestamp: now, value: 512, unit: .bytesPerSecond),
                MetricSample(metricID: .networkInBytesPerSec, timestamp: now.addingTimeInterval(1), value: impossible, unit: .bytesPerSecond)
            ],
            outbound: [
                MetricSample(metricID: .networkOutBytesPerSec, timestamp: now, value: 256, unit: .bytesPerSecond),
                MetricSample(metricID: .networkOutBytesPerSec, timestamp: now.addingTimeInterval(1), value: .infinity, unit: .bytesPerSecond)
            ],
            window: .oneHour
        )

        XCTAssertEqual(store.inboundSamples.map(\.value), [512])
        XCTAssertEqual(store.outboundSamples.map(\.value), [256])
    }

    func testTemperatureFeatureStoreBuildsAggregateRowsAndExcludesFanChannels() {
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
            temperatureHistoryStoreStatusMessage: nil,
            latestCapturedAt: now,
            usingPersistedSnapshot: false
        )

        XCTAssertEqual(store.groupedSensors.map(\.category), [.battery, .cpu])
        XCTAssertEqual(store.groupedSensors.first?.aggregateRows.map(\.displayName), ["Battery"])
        XCTAssertEqual(store.groupedSensors.first?.aggregateRows.map(\.sourceSensorCount), [1])
        XCTAssertEqual(store.groupedSensors.last?.channels.map(\.id), ["cpu-1", "cpu-2"])
        XCTAssertEqual(store.groupedSensors.last?.aggregateRows.map(\.displayName), ["CPU Max", "CPU Avg", "CPU Min"])
        XCTAssertEqual(store.groupedSensors.last?.aggregateRows.map(\.sourceSensorCount), [2, 2, 2])
        let values = store.groupedSensors.last?.aggregateRows.map(\.value) ?? []
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values[0], 81, accuracy: 0.01)
        XCTAssertEqual(values[1], 78.5, accuracy: 0.01)
        XCTAssertEqual(values[2], 76, accuracy: 0.01)
        XCTAssertNil(store.groupedSensors.last?.maxValueByChannelType[.fanRPM])
        XCTAssertEqual(store.groupedSensors.last?.maxValueByChannelType[.temperatureCelsius], 81)
    }

    func testTemperatureFeatureStoreSkipsCalibrationAndThirtyDegreeSentinelChannels() {
        let store = TemperatureFeatureStore()
        let now = Date(timeIntervalSince1970: 1_700_000_200)
        let sensors = [
            SensorReading(id: "pmu-tcal", rawName: "PMU tcal", displayName: "PMU tcal", category: .cpu, channelType: .temperatureCelsius, value: 51.85, source: "test", timestamp: now),
            SensorReading(id: "cpu-1", rawName: "PMU tdie1", displayName: "CPU Core Die 1", category: .cpu, channelType: .temperatureCelsius, value: 55, source: "test", timestamp: now),
            SensorReading(id: "gpu-sentinel", rawName: "GPU MTR Temp Sensor1", displayName: "GPU Sensor 1", category: .gpu, channelType: .temperatureCelsius, value: 30, source: "test", timestamp: now),
            SensorReading(id: "gpu-real", rawName: "GPU MTR Temp Sensor4", displayName: "GPU Sensor 4", category: .gpu, channelType: .temperatureCelsius, value: 47, source: "test", timestamp: now)
        ]

        store.update(
            visibleSensors: sensors,
            privilegedTemperatureStatusMessage: nil,
            privilegedTemperatureLastSuccessMessage: nil,
            privilegedTemperatureHealthy: true,
            privilegedSourceDiagnostics: [],
            fanParityGateBlocked: false,
            fanParityGateMessage: nil,
            temperatureHistoryStoreStatusMessage: nil,
            latestCapturedAt: now,
            usingPersistedSnapshot: false
        )

        XCTAssertEqual(store.groupedSensors.map(\.category), [.cpu, .gpu])
        XCTAssertEqual(store.groupedSensors.first?.channels.map(\.id), ["cpu-1"])
        XCTAssertEqual(store.groupedSensors.first?.aggregateRows.map(\.displayName), ["CPU"])
        XCTAssertEqual(store.groupedSensors.last?.channels.map(\.id), ["gpu-real"])
        XCTAssertEqual(store.groupedSensors.last?.aggregateRows.map(\.displayName), ["GPU"])
    }

    func testTemperatureFeatureStoreCollapsesIdenticalAggregateRows() {
        let store = TemperatureFeatureStore()
        let now = Date(timeIntervalSince1970: 1_700_000_300)
        let sensors = [
            SensorReading(id: "storage-1", rawName: "NAND CH0 temp", displayName: "SSD 1", category: .storage, channelType: .temperatureCelsius, value: 43, source: "test", timestamp: now),
            SensorReading(id: "storage-2", rawName: "NAND CH1 temp", displayName: "SSD 2", category: .storage, channelType: .temperatureCelsius, value: 43, source: "test", timestamp: now)
        ]

        store.update(
            visibleSensors: sensors,
            privilegedTemperatureStatusMessage: nil,
            privilegedTemperatureLastSuccessMessage: nil,
            privilegedTemperatureHealthy: true,
            privilegedSourceDiagnostics: [],
            fanParityGateBlocked: false,
            fanParityGateMessage: nil,
            temperatureHistoryStoreStatusMessage: nil,
            latestCapturedAt: now,
            usingPersistedSnapshot: false
        )

        XCTAssertEqual(store.groupedSensors.first?.aggregateRows.map(\.displayName), ["Storage"])
        XCTAssertEqual(store.groupedSensors.first?.aggregateRows.first?.id, TemperatureAggregateRow.id(category: .storage, statistic: .avg))
        XCTAssertEqual(store.groupedSensors.first?.aggregateRows.first?.sourceSensorCount, 2)
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
