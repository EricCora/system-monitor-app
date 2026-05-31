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

    func testDownsampleUsesWallClockBuckets() {
        let bucketSeconds = 30
        let base = Date(timeIntervalSince1970: 1_000)
        let input = [
            MetricSample(metricID: .cpuTotalPercent, timestamp: base.addingTimeInterval(5), value: 10, unit: .percent),
            MetricSample(metricID: .cpuTotalPercent, timestamp: base.addingTimeInterval(15), value: 20, unit: .percent),
            MetricSample(metricID: .cpuTotalPercent, timestamp: base.addingTimeInterval(35), value: 30, unit: .percent),
            MetricSample(metricID: .cpuTotalPercent, timestamp: base.addingTimeInterval(45), value: 40, unit: .percent)
        ]

        let output = Downsampler.downsample(input, maxPoints: 2, bucketSeconds: bucketSeconds)

        XCTAssertEqual(output.count, 2)
        XCTAssertEqual(output[0].timestamp, Downsampler.bucketTimestamp(input[0].timestamp, bucketSeconds: bucketSeconds))
        XCTAssertEqual(output[1].timestamp, Downsampler.bucketTimestamp(input[2].timestamp, bucketSeconds: bucketSeconds))
        XCTAssertEqual(output[0].value, 15, accuracy: 0.001)
        XCTAssertEqual(output[1].value, 35, accuracy: 0.001)
    }

    func testDownsampleHistoryPreservesPastBucketsWhenNewSampleArrives() {
        let bucketSeconds = 30
        let base = Date(timeIntervalSince1970: 10_000)
        let initial = (0..<4).map { index in
            MetricHistoryPoint(
                timestamp: base.addingTimeInterval(Double(index * bucketSeconds + 5)),
                value: Double(index * 10),
                unit: .percent
            )
        }
        let extended = initial + [
            MetricHistoryPoint(
                timestamp: base.addingTimeInterval(Double(4 * bucketSeconds + 5)),
                value: 99,
                unit: .percent
            )
        ]

        let first = Downsampler.downsampleHistory(initial, maxPoints: 10, bucketSeconds: bucketSeconds)
        let second = Downsampler.downsampleHistory(extended, maxPoints: 10, bucketSeconds: bucketSeconds)

        let sharedTimestamps = Set(first.map(\.timestamp))
        for point in second where sharedTimestamps.contains(point.timestamp) {
            let previous = first.first { $0.timestamp == point.timestamp }
            XCTAssertEqual(previous?.value ?? -1, point.value, accuracy: 0.001)
        }
    }

    func testBucketTimestampAlignsToBucketBoundary() {
        let bucketSeconds = 60
        let timestamp = Date(timeIntervalSince1970: 125)
        let aligned = Downsampler.bucketTimestamp(timestamp, bucketSeconds: bucketSeconds)
        XCTAssertEqual(aligned.timeIntervalSince1970, 120, accuracy: 0.001)
    }
}
