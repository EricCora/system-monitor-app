import XCTest
import SQLite3
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
        let series = await reopened.samples(
            for: .cpuUserPercent,
            window: .oneHour,
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

    func testLatestByMetricPersistsAcrossRelaunch() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("metric-history-latest-reopen-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let store = MetricHistoryStore(databaseURL: databaseURL)
        let start = Date(timeIntervalSince1970: 1_700_200_000)

        await store.append(samples: [
            MetricSample(metricID: .cpuLoadAverage1, timestamp: start, value: 2.5, unit: .scalar),
            MetricSample(metricID: .cpuLoadAverage1, timestamp: start.addingTimeInterval(15), value: 4.25, unit: .scalar),
            MetricSample(metricID: .batteryChargePercent, timestamp: start.addingTimeInterval(20), value: 81, unit: .percent)
        ], now: start.addingTimeInterval(20))

        let reopened = MetricHistoryStore(databaseURL: databaseURL)
        let latest = await reopened.latestByMetric()

        XCTAssertEqual(latest[.cpuLoadAverage1]?.value ?? -1, 4.25, accuracy: 0.01)
        XCTAssertEqual(latest[.batteryChargePercent]?.value ?? -1, 81, accuracy: 0.01)
    }

    func testReopenInvalidatesLegacyMemoryPressureHistoryOnlyOnce() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("metric-history-pressure-migration-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let start = Date(timeIntervalSince1970: 1_700_300_000)
        try seedLegacyMetricHistoryDatabase(at: databaseURL, start: start)

        let reopened = MetricHistoryStore(databaseURL: databaseURL)
        let pressureSeries = await reopened.samples(
            for: .memoryPressureLevel,
            window: .oneHour,
            now: start.addingTimeInterval(10),
            maxPoints: 10
        )
        let latestAfterMigration = await reopened.latestByMetric()

        XCTAssertTrue(pressureSeries.isEmpty)
        XCTAssertNil(latestAfterMigration[.memoryPressureLevel])
        XCTAssertEqual(latestAfterMigration[.cpuTotalPercent]?.value ?? -1, 22, accuracy: 0.01)

        await reopened.append(samples: [
            MetricSample(metricID: .memoryPressureLevel, timestamp: start.addingTimeInterval(20), value: 55, unit: .percent)
        ], now: start.addingTimeInterval(20))

        let reopenedAgain = MetricHistoryStore(databaseURL: databaseURL)
        let migratedSeries = await reopenedAgain.samples(
            for: .memoryPressureLevel,
            window: .oneHour,
            now: start.addingTimeInterval(30),
            maxPoints: 10
        )

        XCTAssertEqual(migratedSeries.count, 1)
        XCTAssertEqual(migratedSeries.first?.value ?? -1, 55, accuracy: 0.01)
    }

    private func seedLegacyMetricHistoryDatabase(at databaseURL: URL, start: Date) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        let schemaSQL = """
        CREATE TABLE metric_samples(
            metric_id TEXT NOT NULL,
            unit TEXT NOT NULL,
            value REAL NOT NULL,
            ts INTEGER NOT NULL,
            PRIMARY KEY(metric_id, ts)
        );
        CREATE INDEX idx_metric_samples_lookup
            ON metric_samples(metric_id, ts);
        CREATE TABLE latest_metric_samples(
            metric_id TEXT PRIMARY KEY,
            unit TEXT NOT NULL,
            value REAL NOT NULL,
            ts INTEGER NOT NULL
        );
        """
        XCTAssertEqual(sqlite3_exec(db, schemaSQL, nil, nil, nil), SQLITE_OK)

        let insertSQL = """
        INSERT INTO metric_samples(metric_id, unit, value, ts) VALUES
            ('memoryPressureLevel', 'percent', 91, \(Int64(start.timeIntervalSince1970))),
            ('cpuTotalPercent', 'percent', 22, \(Int64(start.timeIntervalSince1970)));
        INSERT INTO latest_metric_samples(metric_id, unit, value, ts) VALUES
            ('memoryPressureLevel', 'percent', 91, \(Int64(start.timeIntervalSince1970))),
            ('cpuTotalPercent', 'percent', 22, \(Int64(start.timeIntervalSince1970)));
        """
        XCTAssertEqual(sqlite3_exec(db, insertSQL, nil, nil, nil), SQLITE_OK)
    }
}
