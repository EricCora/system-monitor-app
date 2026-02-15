import Foundation
import XCTest
@testable import PulseBarCore

final class DownsamplerTests: XCTestCase {
    func testDownsampleReturnsOriginalWhenBelowLimit() {
        let now = Date()
        let input = [
            MetricSample(metricID: .cpuTotalPercent, timestamp: now, value: 10, unit: .percent),
            MetricSample(metricID: .cpuTotalPercent, timestamp: now.addingTimeInterval(1), value: 20, unit: .percent)
        ]

        let output = Downsampler.downsample(input, maxPoints: 10)
        XCTAssertEqual(output.count, input.count)
        XCTAssertEqual(output.map(\.value), [10, 20])
    }

    func testDownsampleCapsPointCount() {
        let now = Date()
        let input = (0..<100).map {
            MetricSample(
                metricID: .cpuTotalPercent,
                timestamp: now.addingTimeInterval(Double($0)),
                value: Double($0),
                unit: .percent
            )
        }

        let output = Downsampler.downsample(input, maxPoints: 20)
        XCTAssertLessThanOrEqual(output.count, 20)
    }

    func testDownsampleAveragesBuckets() {
        let now = Date()
        let input = [0.0, 10.0, 20.0, 30.0].enumerated().map { index, value in
            MetricSample(
                metricID: .cpuTotalPercent,
                timestamp: now.addingTimeInterval(Double(index)),
                value: value,
                unit: .percent
            )
        }

        let output = Downsampler.downsample(input, maxPoints: 2)
        XCTAssertEqual(output.count, 2)
        XCTAssertEqual(output.map(\.value), [5.0, 25.0])
    }
}
