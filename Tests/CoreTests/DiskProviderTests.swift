import XCTest
@testable import PulseBarCore

final class DiskProviderTests: XCTestCase {
    func testParsesSMARTStatusCode() {
        let verifiedOutput = """
        Device Identifier: disk3s1
        SMART Status: Verified
        """

        let failingOutput = """
        Device Identifier: disk3s1
        SMART Status: Failing
        """

        let unsupportedOutput = """
        Device Identifier: disk3s1
        SMART Status: Not Supported
        """

        XCTAssertEqual(DiskProvider.parseSMARTStatusCode(from: verifiedOutput), 1)
        XCTAssertEqual(DiskProvider.parseSMARTStatusCode(from: failingOutput), -1)
        XCTAssertEqual(DiskProvider.parseSMARTStatusCode(from: unsupportedOutput), 0)
    }

    func testParsesIOKitStatisticsCounters() {
        let statistics: [String: Any] = [
            "Bytes (Read)": NSNumber(value: 1_000),
            "Bytes (Write)": NSNumber(value: 2_000)
        ]

        let parsed = DiskProvider.parseIOKitStatistics(statistics)
        XCTAssertEqual(parsed?.readBytes, 1_000)
        XCTAssertEqual(parsed?.writeBytes, 2_000)
    }

    func testParseByteCounterHandlesNumericTypes() {
        XCTAssertEqual(DiskProvider.parseByteCounter(NSNumber(value: 44)), 44)
        XCTAssertEqual(DiskProvider.parseByteCounter(UInt64(99)), 99)
        XCTAssertEqual(DiskProvider.parseByteCounter("123"), 123)
        XCTAssertNil(DiskProvider.parseByteCounter(nil))
    }
}
