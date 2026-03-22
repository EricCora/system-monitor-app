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

    func testByteFormattingClampsValuesAboveInt64Range() {
        let maxText = UnitsFormatter.formatBytes(Double(Int64.max))
        let overflowText = UnitsFormatter.formatBytes(Double(Int64.max) * 2)

        XCTAssertEqual(overflowText, maxText)
    }

    func testThroughputFormattingSanitizesNonFiniteValues() {
        let zeroBytesText = UnitsFormatter.format(0, unit: .bytesPerSecond, throughputUnit: .bytesPerSecond)
        let zeroBitsText = UnitsFormatter.format(0, unit: .bytesPerSecond, throughputUnit: .bitsPerSecond)

        XCTAssertEqual(
            UnitsFormatter.format(.infinity, unit: .bytesPerSecond, throughputUnit: .bytesPerSecond),
            zeroBytesText
        )
        XCTAssertEqual(
            UnitsFormatter.format(.infinity, unit: .bytesPerSecond, throughputUnit: .bitsPerSecond),
            zeroBitsText
        )
        XCTAssertEqual(
            UnitsFormatter.format(.nan, unit: .bytesPerSecond, throughputUnit: .bytesPerSecond),
            zeroBytesText
        )
    }

    func testCelsiusFormatting() {
        XCTAssertEqual(UnitsFormatter.format(56.42, unit: .celsius), "56.4 C")
    }

    func testMilliampsFormatting() {
        XCTAssertEqual(UnitsFormatter.format(1234.4, unit: .milliamps), "1234 mA")
    }

    func testWattsFormatting() {
        XCTAssertEqual(UnitsFormatter.format(18.25, unit: .watts), "18.2 W")
    }

    func testMinutesFormatting() {
        XCTAssertEqual(UnitsFormatter.format(45, unit: .minutes), "45m")
        XCTAssertEqual(UnitsFormatter.format(125, unit: .minutes), "2h 5m")
    }
}
