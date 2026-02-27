import XCTest
@testable import PulseBarCore

final class UnitsFormatterTests: XCTestCase {
    func testPercentFormatting() {
        XCTAssertEqual(UnitsFormatter.format(42.3, unit: .percent), "42%")
    }

    func testBytesFormattingIncludesUnit() {
        let formatted = UnitsFormatter.format(1_048_576, unit: .bytes)
        XCTAssertTrue(formatted.contains("MB") || formatted.contains("MiB"))
    }

    func testThroughputRespectsDisplayUnit() {
        let bytesText = UnitsFormatter.format(1000, unit: .bytesPerSecond, throughputUnit: .bytesPerSecond)
        let bitsText = UnitsFormatter.format(1000, unit: .bytesPerSecond, throughputUnit: .bitsPerSecond)

        XCTAssertNotEqual(bytesText, bitsText)
        XCTAssertTrue(bitsText.contains("b/s"))
    }

    func testCelsiusFormatting() {
        XCTAssertEqual(UnitsFormatter.format(56.42, unit: .celsius), "56.4 C")
    }

    func testMilliampsFormatting() {
        XCTAssertEqual(UnitsFormatter.format(1234.4, unit: .milliamps), "1234 mA")
    }

    func testMinutesFormatting() {
        XCTAssertEqual(UnitsFormatter.format(45, unit: .minutes), "45m")
        XCTAssertEqual(UnitsFormatter.format(125, unit: .minutes), "2h 5m")
    }
}
