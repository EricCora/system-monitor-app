import XCTest
@testable import PulseBarCore

final class AlertRuleTests: XCTestCase {
    func testDecodingRuleWithoutComparisonDefaultsToAboveOrEqual() throws {
        let legacyJSON = """
        {
          "metricID": { "cpuTotalPercent": {} },
          "threshold": 85,
          "durationSeconds": 30,
          "isEnabled": true
        }
        """

        let decoded = try JSONDecoder().decode(AlertRule.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.metricID, .cpuTotalPercent)
        XCTAssertEqual(decoded.comparison, .aboveOrEqual)
    }
}
