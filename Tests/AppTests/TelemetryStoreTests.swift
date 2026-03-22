import XCTest
@testable import PulseBarApp

@MainActor
final class TelemetryStoreTests: XCTestCase {
    func testRecordTemperatureHistoryAppendAdvancesRevision() {
        let store = TelemetryStore()

        XCTAssertEqual(store.temperatureHistoryRevision, 0)

        store.recordTemperatureHistoryAppend()
        XCTAssertEqual(store.temperatureHistoryRevision, 1)

        store.recordTemperatureHistoryAppend()
        XCTAssertEqual(store.temperatureHistoryRevision, 2)
    }
}
