import XCTest
@testable import PulseBarCore

final class MemoryHistoryStoreTests: XCTestCase {
    func testAppendAndSeriesWithinWindow() async {
        let store = MemoryHistoryStore(databaseURL: temporaryDatabaseURL())
        let now = Date()

        await store.append(point: makePoint(timestamp: now.addingTimeInterval(-300), appBytes: 100, wiredBytes: 80, activeBytes: 120, compressedBytes: 40, cacheBytes: 20, freeBytes: 60, totalBytes: 400, pressurePercent: 55))
        await store.append(point: makePoint(timestamp: now.addingTimeInterval(-120), appBytes: 105, wiredBytes: 82, activeBytes: 122, compressedBytes: 41, cacheBytes: 21, freeBytes: 58, totalBytes: 400, pressurePercent: 56))
        await store.append(point: makePoint(timestamp: now.addingTimeInterval(-30), appBytes: 110, wiredBytes: 85, activeBytes: 126, compressedBytes: 43, cacheBytes: 22, freeBytes: 54, totalBytes: 400, pressurePercent: 58))

        let series = await store.series(window: .oneHour, now: now, maxPoints: 900)

        XCTAssertEqual(series.count, 3)
        XCTAssertLessThanOrEqual(
            abs((series.first?.timestamp.timeIntervalSince(now.addingTimeInterval(-300)) ?? 99)),
            1.0
        )
        XCTAssertLessThanOrEqual(
            abs((series.last?.timestamp.timeIntervalSince(now.addingTimeInterval(-30)) ?? 99)),
            1.0
        )
    }

    func testBucketedSeriesAndDownsampling() async {
        let store = MemoryHistoryStore(databaseURL: temporaryDatabaseURL())
        let now = Date()

        for offset in stride(from: 0, through: 3_600, by: 30) {
            let timestamp = now.addingTimeInterval(TimeInterval(-offset))
            await store.append(
                point: makePoint(
                    timestamp: timestamp,
                    appBytes: Double(200 + offset),
                    wiredBytes: 100,
                    activeBytes: 180,
                    compressedBytes: 70,
                    cacheBytes: 40,
                    freeBytes: 120,
                    totalBytes: 600,
                    pressurePercent: 65
                )
            )
        }

        let bucketed = await store.series(window: .oneDay, now: now, maxPoints: 900)
        let downsampled = await store.series(window: .oneDay, now: now, maxPoints: 8)

        XCTAssertFalse(bucketed.isEmpty)
        XCTAssertLessThan(bucketed.count, 121)
        XCTAssertLessThanOrEqual(downsampled.count, 8)
        XCTAssertLessThanOrEqual(downsampled.count, bucketed.count)
    }

    func testPrunesDataOlderThanRetentionWindow() async {
        let store = MemoryHistoryStore(databaseURL: temporaryDatabaseURL())
        let oldTimestamp = Date().addingTimeInterval(-50 * 24 * 60 * 60)

        await store.append(
            point: makePoint(
                timestamp: oldTimestamp,
                appBytes: 1,
                wiredBytes: 1,
                activeBytes: 1,
                compressedBytes: 1,
                cacheBytes: 1,
                freeBytes: 1,
                totalBytes: 5,
                pressurePercent: 20
            )
        )

        let historicalNow = oldTimestamp.addingTimeInterval(60 * 60)
        let result = await store.series(window: .oneHour, now: historicalNow, maxPoints: 900)
        XCTAssertTrue(result.isEmpty)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("memory-history-\(UUID().uuidString).sqlite3")
    }

    private func makePoint(
        timestamp: Date,
        appBytes: Double,
        wiredBytes: Double,
        activeBytes: Double,
        compressedBytes: Double,
        cacheBytes: Double,
        freeBytes: Double,
        totalBytes: Double,
        pressurePercent: Double
    ) -> MemoryHistoryPoint {
        MemoryHistoryPoint(
            timestamp: timestamp,
            appBytes: appBytes,
            wiredBytes: wiredBytes,
            activeBytes: activeBytes,
            compressedBytes: compressedBytes,
            cacheBytes: cacheBytes,
            freeBytes: freeBytes,
            totalBytes: totalBytes,
            pressurePercent: pressurePercent
        )
    }
}
