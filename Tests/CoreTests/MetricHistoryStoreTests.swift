import XCTest
@testable import PulseBarCore

final class MetricHistoryStoreTests: XCTestCase {
    func testAppendAndQuerySeriesAcrossRelaunch() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("metric-history-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let store = MetricHistoryStore(databaseURL: databaseURL)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        await store.append(samples: [
            MetricSample(metricID: .cpuUserPercent, timestamp: start, value: 20, unit: .percent),
            MetricSample(metricID: .cpuUserPercent, timestamp: start.addingTimeInterval(60), value: 40, unit: .percent)
        ], now: start.addingTimeInterval(60))

        let reopened = MetricHistoryStore(databaseURL: databaseURL)
        let series = await reopened.series(
            for: .cpuUserPercent,
            window: TimeWindow.oneHour,
            now: start.addingTimeInterval(120),
            maxPoints: 10
        )

        XCTAssertEqual(series.count, 2)
        XCTAssertEqual(series.last?.value ?? -1, 40, accuracy: 0.01)
    }

    func testLatestByMetricReturnsMostRecentSample() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("metric-history-latest-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let store = MetricHistoryStore(databaseURL: databaseURL)
        let start = Date(timeIntervalSince1970: 1_700_100_000)

        await store.append(samples: [
            MetricSample(metricID: .cpuTotalPercent, timestamp: start, value: 10, unit: .percent),
            MetricSample(metricID: .cpuTotalPercent, timestamp: start.addingTimeInterval(10), value: 33, unit: .percent)
        ], now: start.addingTimeInterval(10))

        let latest = await store.latestByMetric()
        XCTAssertEqual(latest[.cpuTotalPercent]?.value ?? -1, 33, accuracy: 0.01)
    }
}
