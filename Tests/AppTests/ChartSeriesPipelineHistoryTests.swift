import XCTest
@testable import PulseBarApp
import PulseBarCore

final class ChartSeriesPipelineHistoryTests: XCTestCase {
    func testPrepareMetricHistoryPreservesPastBucketsWhenExtended() {
        let bucketSeconds = ChartWindow.sixHours.bucketSeconds
        let base = Date(timeIntervalSince1970: 50_000)
        let initial = (0..<4).map { index in
            MetricHistoryPoint(
                timestamp: base.addingTimeInterval(Double(index * bucketSeconds + 2)),
                value: Double(index),
                unit: .percent
            )
        }
        let extended = initial + [
            MetricHistoryPoint(
                timestamp: base.addingTimeInterval(Double(4 * bucketSeconds + 2)),
                value: 99,
                unit: .percent
            )
        ]

        let first = ChartSeriesPipeline.prepareMetricHistory(
            initial,
            maxPoints: 10,
            bucketSeconds: bucketSeconds,
            smoothingAlpha: 1.0
        )
        let second = ChartSeriesPipeline.prepareMetricHistory(
            extended,
            maxPoints: 10,
            bucketSeconds: bucketSeconds,
            smoothingAlpha: 1.0
        )

        let sharedTimestamps = Set(first.map(\.timestamp))
        for point in second where sharedTimestamps.contains(point.timestamp) {
            let previous = first.first { $0.timestamp == point.timestamp }
            XCTAssertEqual(previous?.value ?? -1, point.value, accuracy: 0.001)
        }
    }

    func testPrepareCPUUsageHistoryAlignsUserAndSystemTimestamps() {
        let base = Date(timeIntervalSince1970: 20_000)
        let user = [
            MetricHistoryPoint(timestamp: base, value: 30, unit: .percent),
            MetricHistoryPoint(timestamp: base.addingTimeInterval(30), value: 40, unit: .percent),
            MetricHistoryPoint(timestamp: base.addingTimeInterval(90), value: 50, unit: .percent)
        ]
        let system = [
            MetricHistoryPoint(timestamp: base.addingTimeInterval(5), value: 20, unit: .percent),
            MetricHistoryPoint(timestamp: base.addingTimeInterval(60), value: 25, unit: .percent)
        ]

        let aligned = ChartSeriesPipeline.prepareCPUUsageHistory(
            userHistory: user,
            systemHistory: system,
            maxPoints: 10,
            bucketSeconds: 30,
            smoothingAlpha: 1.0
        )

        XCTAssertEqual(Set(aligned.user.map(\.timestamp)), Set(aligned.system.map(\.timestamp)))
        XCTAssertEqual(aligned.user.count, aligned.system.count)

        let model = PreparedTimeSeriesChartModel.fromCPUUsage(
            userHistory: user,
            systemHistory: system,
            window: .sixHours,
            smoothingAlpha: 1.0
        )
        let userTimestamps = Set(model.points.filter { $0.seriesKey == "cpu.user" }.map(\.timestamp))
        let systemTimestamps = Set(model.points.filter { $0.seriesKey == "cpu.system" }.map(\.timestamp))
        XCTAssertEqual(userTimestamps, systemTimestamps)
    }

    func testFromCPUUsageUsesWindowBucketSecondsForAlignment() {
        let base = Date(timeIntervalSince1970: 30_000)
        let user = [
            MetricHistoryPoint(timestamp: base, value: 10, unit: .percent),
            MetricHistoryPoint(timestamp: base.addingTimeInterval(30), value: 20, unit: .percent)
        ]
        let system = [
            MetricHistoryPoint(timestamp: base.addingTimeInterval(15), value: 5, unit: .percent),
            MetricHistoryPoint(timestamp: base.addingTimeInterval(45), value: 15, unit: .percent)
        ]

        let model = PreparedTimeSeriesChartModel.fromCPUUsage(
            userHistory: user,
            systemHistory: system,
            window: .sixHours,
            smoothingAlpha: 1.0
        )

        let expectedBucket = Downsampler.bucketTimestamp(base, bucketSeconds: ChartWindow.sixHours.bucketSeconds)
        XCTAssertTrue(model.points.contains { $0.timestamp == expectedBucket })
        XCTAssertEqual(
            Set(model.points.filter { $0.seriesKey == "cpu.user" }.map(\.timestamp)),
            Set(model.points.filter { $0.seriesKey == "cpu.system" }.map(\.timestamp))
        )
    }

    func testCompactCPUUsagePointsEmitSystemNotTotal() {
        let now = Date(timeIntervalSince1970: 2_000)
        let renderModel = CompactCPUUsageRenderModel(
            xDomain: now...(now.addingTimeInterval(120)),
            segments: [
                CompactChartSegment(points: [
                    CompactCPUUsagePoint(timestamp: now, userValue: 30, systemValue: 20, totalValue: 50),
                    CompactCPUUsagePoint(
                        timestamp: now.addingTimeInterval(60),
                        userValue: 40,
                        systemValue: 10,
                        totalValue: 50
                    )
                ])
            ]
        )

        let points = ChartSeriesPipeline.compactCPUUsagePoints(renderModel: renderModel)
        let systemValues = points.filter { $0.seriesKey == "cpu.system" }.sorted { $0.timestamp < $1.timestamp }.map(\.value)
        let userValues = points.filter { $0.seriesKey == "cpu.user" }.sorted { $0.timestamp < $1.timestamp }.map(\.value)

        XCTAssertEqual(systemValues, [20, 10])
        XCTAssertEqual(userValues, [30, 40])
    }
}
