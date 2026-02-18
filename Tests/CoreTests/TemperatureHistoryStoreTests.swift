import Foundation
import XCTest
@testable import PulseBarCore

final class TemperatureHistoryStoreTests: XCTestCase {
    func testStoresAndReadsRawOneHourSeries() async throws {
        let url = tempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = TemperatureHistoryStore(databaseURL: url)
        let startupError = await store.startupError()
        XCTAssertNil(startupError)

        let sensorID = "iohid:temperatureCelsius:test-sensor"
        let now = Date()

        let channels = (0..<5).map { index in
            SensorReading(
                id: sensorID,
                rawName: "Test Sensor",
                displayName: "Test Sensor",
                category: .cpu,
                channelType: .temperatureCelsius,
                value: 40 + Double(index),
                source: "iohid",
                timestamp: now.addingTimeInterval(Double(index))
            )
        }

        await store.append(channels: channels)
        let points = await store.series(
            sensorID: sensorID,
            channelType: .temperatureCelsius,
            window: .oneHour,
            now: now.addingTimeInterval(10),
            maxPoints: 100
        )

        XCTAssertEqual(points.count, 5)
        XCTAssertEqual(points.first?.value ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(points.last?.value ?? -1, 44, accuracy: 0.001)
    }

    func testTwentyFourHourWindowBucketsByMinute() async throws {
        let url = tempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = TemperatureHistoryStore(databaseURL: url)
        let startupError = await store.startupError()
        XCTAssertNil(startupError)

        let sensorID = "iohid:temperatureCelsius:bucket-sensor"
        let roundedMinute = floor(Date().timeIntervalSince1970 / 60) * 60
        let base = Date(timeIntervalSince1970: roundedMinute)

        let channels = [
            SensorReading(
                id: sensorID,
                rawName: "Bucket Sensor",
                displayName: "Bucket Sensor",
                category: .cpu,
                channelType: .temperatureCelsius,
                value: 50,
                source: "iohid",
                timestamp: base
            ),
            SensorReading(
                id: sensorID,
                rawName: "Bucket Sensor",
                displayName: "Bucket Sensor",
                category: .cpu,
                channelType: .temperatureCelsius,
                value: 54,
                source: "iohid",
                timestamp: base.addingTimeInterval(20)
            ),
            SensorReading(
                id: sensorID,
                rawName: "Bucket Sensor",
                displayName: "Bucket Sensor",
                category: .cpu,
                channelType: .temperatureCelsius,
                value: 60,
                source: "iohid",
                timestamp: base.addingTimeInterval(70)
            )
        ]

        await store.append(channels: channels)
        let points = await store.series(
            sensorID: sensorID,
            channelType: .temperatureCelsius,
            window: .twentyFourHours,
            now: base.addingTimeInterval(120),
            maxPoints: 100
        )

        XCTAssertGreaterThanOrEqual(points.count, 2)
        if points.count >= 2 {
            XCTAssertEqual(points[0].value, 52, accuracy: 0.001)
            XCTAssertEqual(points[1].value, 60, accuracy: 0.001)
        }
    }

    private func tempDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pulsebar-history-\(UUID().uuidString).sqlite3")
    }
}
