import XCTest
@testable import PulseBarCore

final class PowermetricsParserTests: XCTestCase {
    func testParserExtractsPrimaryAndMaxTemperatures() throws {
        let parser = PowermetricsTemperatureParser()
        let output = """
        CPU die temperature: 62.50 C
        GPU die temperature: 55.25 C
        SOC temperature: 64.00 C
        """

        let reading = try parser.parse(output)
        XCTAssertEqual(reading.primaryCelsius, 62.50, accuracy: 0.01)
        XCTAssertEqual(reading.maxCelsius, 64.00, accuracy: 0.01)
        XCTAssertEqual(reading.sensorCount, 3)
    }

    func testParserThrowsForMissingTemperatureData() {
        let parser = PowermetricsTemperatureParser()
        let output = "powermetrics run without any temperature values"

        XCTAssertThrowsError(try parser.parse(output))
    }
}
