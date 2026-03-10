import XCTest
@testable import PulseBarApp
import PulseBarCore

final class ChartSeriesSanitizerTests: XCTestCase {
    func testMetricHistorySortsAscendingAndKeepsLastDuplicateTimestamp() {
        let early = Date(timeIntervalSince1970: 100)
        let late = Date(timeIntervalSince1970: 200)

        let points = [
            MetricHistoryPoint(timestamp: late, value: 2, unit: .percent),
            MetricHistoryPoint(timestamp: early, value: 1, unit: .percent),
            MetricHistoryPoint(timestamp: late, value: 3, unit: .percent)
        ]

        let sanitized = ChartSeriesPipeline.sanitize(points, timestamp: \.timestamp)

        XCTAssertEqual(sanitized.map(\.timestamp), [early, late])
        XCTAssertEqual(sanitized.map(\.value), [1, 3])
    }

    func testMetricSamplesSortAscendingAndKeepsLastDuplicateTimestamp() {
        let early = Date(timeIntervalSince1970: 100)
        let late = Date(timeIntervalSince1970: 200)

        let samples = [
            MetricSample(metricID: .cpuLoadAverage1, timestamp: late, value: 2, unit: .scalar),
            MetricSample(metricID: .cpuLoadAverage1, timestamp: early, value: 1, unit: .scalar),
            MetricSample(metricID: .cpuLoadAverage1, timestamp: late, value: 3, unit: .scalar)
        ]

        let sanitized = ChartSeriesPipeline.sanitize(samples, timestamp: \.timestamp)

        XCTAssertEqual(sanitized.map(\.timestamp), [early, late])
        XCTAssertEqual(sanitized.map(\.value), [1, 3])
    }
}
