import XCTest
@testable import PulseBarCore

final class ChartWindowTests: XCTestCase {
    func testLegacyRawValueMigrationMapsToSharedChartWindows() {
        XCTAssertEqual(ChartWindow(legacyRawValue: "fiveMinutes"), .fifteenMinutes)
        XCTAssertEqual(ChartWindow(legacyRawValue: "fifteenMinutes"), .fifteenMinutes)
        XCTAssertEqual(ChartWindow(legacyRawValue: "oneHour"), .oneHour)
        XCTAssertEqual(ChartWindow(legacyRawValue: "twentyFourHours"), .oneDay)
        XCTAssertEqual(ChartWindow(legacyRawValue: "sevenDays"), .oneWeek)
        XCTAssertEqual(ChartWindow(legacyRawValue: "thirtyDays"), .oneMonth)
    }

    func testBucketSecondsMatchUnifiedResolutionRules() {
        XCTAssertEqual(ChartWindow.fifteenMinutes.bucketSeconds, 1)
        XCTAssertEqual(ChartWindow.oneHour.bucketSeconds, 1)
        XCTAssertEqual(ChartWindow.sixHours.bucketSeconds, 30)
        XCTAssertEqual(ChartWindow.oneDay.bucketSeconds, 60)
        XCTAssertEqual(ChartWindow.oneWeek.bucketSeconds, 300)
        XCTAssertEqual(ChartWindow.oneMonth.bucketSeconds, 1_800)
    }
}
