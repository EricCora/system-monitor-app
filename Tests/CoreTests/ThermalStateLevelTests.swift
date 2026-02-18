import XCTest
@testable import PulseBarCore

final class ThermalStateLevelTests: XCTestCase {
    func testProcessThermalStateMapping() {
        XCTAssertEqual(ThermalStateLevel.from(processThermalState: .nominal), .nominal)
        XCTAssertEqual(ThermalStateLevel.from(processThermalState: .fair), .fair)
        XCTAssertEqual(ThermalStateLevel.from(processThermalState: .serious), .serious)
        XCTAssertEqual(ThermalStateLevel.from(processThermalState: .critical), .critical)
    }

    func testScalarValueRoundTrip() {
        XCTAssertEqual(ThermalStateLevel.from(metricValue: 0.1), .nominal)
        XCTAssertEqual(ThermalStateLevel.from(metricValue: 1.1), .fair)
        XCTAssertEqual(ThermalStateLevel.from(metricValue: 2.2), .serious)
        XCTAssertEqual(ThermalStateLevel.from(metricValue: 3.0), .critical)
    }
}
