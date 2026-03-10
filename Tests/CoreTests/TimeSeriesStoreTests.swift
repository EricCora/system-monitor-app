import XCTest
@testable import PulseBarCore

final class TimeSeriesStoreTests: XCTestCase {
    func testLatestByMetricUsesNewestSamples() async {
        let store = TimeSeriesStore(defaultCapacity: 8)
        let early = Date(timeIntervalSince1970: 100)
        let late = Date(timeIntervalSince1970: 200)

        await store.append([
            MetricSample(metricID: .cpuTotalPercent, timestamp: early, value: 10, unit: .percent),
            MetricSample(metricID: .cpuTotalPercent, timestamp: late, value: 20, unit: .percent),
            MetricSample(metricID: .memoryPressureLevel, timestamp: late, value: 30, unit: .percent)
        ])

        let latest = await store.latestByMetric()

        XCTAssertEqual(latest[.cpuTotalPercent]?.value, 20)
        XCTAssertEqual(latest[.memoryPressureLevel]?.value, 30)
    }

    func testSeriesReturnsOnlyWindowSuffix() async {
        let store = TimeSeriesStore(defaultCapacity: 8)
        let now = Date()
        await store.append([
            MetricSample(metricID: .cpuTotalPercent, timestamp: now.addingTimeInterval(-7200), value: 1, unit: .percent),
            MetricSample(metricID: .cpuTotalPercent, timestamp: now.addingTimeInterval(-1800), value: 2, unit: .percent),
            MetricSample(metricID: .cpuTotalPercent, timestamp: now.addingTimeInterval(-60), value: 3, unit: .percent)
        ])

        let series = await store.series(for: .cpuTotalPercent, window: .oneHour)

        XCTAssertEqual(series.map(\.value), [2, 3])
    }
}
