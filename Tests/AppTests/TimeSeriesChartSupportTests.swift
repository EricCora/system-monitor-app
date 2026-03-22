import SwiftUI
import XCTest
@testable import PulseBarApp
import PulseBarCore

final class TimeSeriesChartSupportTests: XCTestCase {
    func testMetricHistoryPreservesSeriesIdentityAndSortsWithinSeries() {
        let early = Date(timeIntervalSince1970: 100)
        let middle = Date(timeIntervalSince1970: 150)
        let late = Date(timeIntervalSince1970: 200)

        let points = ChartSeriesPipeline.metricHistory(
            series: [
                ChartMetricSeriesDescriptor(
                    key: "load.1",
                    label: "One Minute",
                    color: .cyan,
                    samples: [
                        MetricHistoryPoint(timestamp: late, value: 4, unit: .scalar),
                        MetricHistoryPoint(timestamp: early, value: 1, unit: .scalar),
                        MetricHistoryPoint(timestamp: late, value: 5, unit: .scalar)
                    ]
                ),
                ChartMetricSeriesDescriptor(
                    key: "load.5",
                    label: "Five Minute",
                    color: .red,
                    samples: [
                        MetricHistoryPoint(timestamp: middle, value: 2, unit: .scalar),
                        MetricHistoryPoint(timestamp: late, value: 3, unit: .scalar)
                    ]
                )
            ]
        )

        let grouped = Dictionary(grouping: points, by: \.seriesLabel)

        XCTAssertEqual(grouped["One Minute"]?.map(\.timestamp), [early, late])
        XCTAssertEqual(grouped["One Minute"]?.map(\.value), [1, 5])
        XCTAssertEqual(grouped["Five Minute"]?.map(\.timestamp), [middle, late])
        XCTAssertEqual(grouped["Five Minute"]?.map(\.value), [2, 3])
    }

    func testMetricSamplesKeepsLastDuplicateTimestampPerSeries() {
        let early = Date(timeIntervalSince1970: 100)
        let late = Date(timeIntervalSince1970: 200)

        let points = ChartSeriesPipeline.metricSamples(
            series: [
                ChartMetricSeriesDescriptor(
                    key: "network.in",
                    label: "Inbound",
                    color: .cyan,
                    samples: [
                        MetricSample(metricID: .networkInBytesPerSec, timestamp: late, value: 4, unit: .bytesPerSecond),
                        MetricSample(metricID: .networkInBytesPerSec, timestamp: early, value: 1, unit: .bytesPerSecond),
                        MetricSample(metricID: .networkInBytesPerSec, timestamp: late, value: 5, unit: .bytesPerSecond)
                    ]
                ),
                ChartMetricSeriesDescriptor(
                    key: "network.out",
                    label: "Outbound",
                    color: .orange,
                    samples: [
                        MetricSample(metricID: .networkOutBytesPerSec, timestamp: early, value: 8, unit: .bytesPerSecond)
                    ]
                )
            ]
        )

        let inbound = points.filter { $0.seriesLabel == "Inbound" }

        XCTAssertEqual(inbound.map(\.timestamp), [early, late])
        XCTAssertEqual(inbound.map(\.value), [1, 5])
        XCTAssertEqual(points.filter { $0.seriesLabel == "Outbound" }.count, 1)
    }

    func testYDomainAddsPaddingForFlatSeries() {
        let points = [
            makePoint(timestamp: Date(timeIntervalSince1970: 100), value: 42, seriesKey: "A", seriesLabel: "A", continuityKey: "A#0"),
            makePoint(timestamp: Date(timeIntervalSince1970: 200), value: 42, seriesKey: "A", seriesLabel: "A", continuityKey: "A#0")
        ]

        let scale = ChartSeriesPipeline.scale(for: points, baseline: .zero(minimumSpan: 1, paddingFraction: 0.12))

        XCTAssertEqual(scale.yDomain.lowerBound, 0)
        XCTAssertEqual(scale.areaBaseline, 0)
        XCTAssertGreaterThan(scale.yDomain.upperBound, 42)
    }

    func testDataMinBaselineTracksVisibleLowerBound() {
        let points = [
            makePoint(timestamp: Date(timeIntervalSince1970: 100), value: 10, seriesKey: "A", seriesLabel: "A", continuityKey: "A#0"),
            makePoint(timestamp: Date(timeIntervalSince1970: 200), value: 20, seriesKey: "A", seriesLabel: "A", continuityKey: "A#0")
        ]

        let scale = ChartSeriesPipeline.scale(for: points, baseline: .dataMin(minimumSpan: 1, paddingFraction: 0.1))

        XCTAssertGreaterThan(scale.yDomain.lowerBound, 0)
        XCTAssertEqual(scale.areaBaseline, scale.yDomain.lowerBound)
        XCTAssertGreaterThan(scale.yDomain.upperBound, 20)
    }

    func testSeriesKeyRemainsIndependentFromDisplayLabel() {
        let points = ChartSeriesPipeline.metricSamples(
            series: [
                ChartMetricSeriesDescriptor(
                    key: "stable-key",
                    label: "Friendly Label",
                    color: .cyan,
                    samples: [MetricSample(metricID: .cpuLoadAverage1, timestamp: Date(timeIntervalSince1970: 1), value: 3, unit: .scalar)]
                )
            ]
        )

        XCTAssertEqual(points.first?.seriesKey, "stable-key")
        XCTAssertEqual(points.first?.seriesLabel, "Friendly Label")
    }

    func testZeroBaselinePolicyStillIncludesNegativeValuesInDomain() {
        let points = [
            makePoint(timestamp: Date(timeIntervalSince1970: 100), value: -12, seriesKey: "battery", seriesLabel: "Battery", continuityKey: "battery#0"),
            makePoint(timestamp: Date(timeIntervalSince1970: 200), value: 8, seriesKey: "battery", seriesLabel: "Battery", continuityKey: "battery#0")
        ]

        let scale = ChartSeriesPipeline.scale(for: points, baseline: .zero(minimumSpan: 1, paddingFraction: 0.1))

        XCTAssertLessThan(scale.yDomain.lowerBound, 0)
        XCTAssertEqual(scale.areaBaseline, 0)
        XCTAssertGreaterThan(scale.yDomain.upperBound, 0)
    }

    func testContinuityKeysSplitWhenLargeGapAppears() {
        let samples = [
            MetricHistoryPoint(timestamp: Date(timeIntervalSince1970: 0), value: 10, unit: .celsius),
            MetricHistoryPoint(timestamp: Date(timeIntervalSince1970: 10), value: 11, unit: .celsius),
            MetricHistoryPoint(timestamp: Date(timeIntervalSince1970: 20), value: 12, unit: .celsius),
            MetricHistoryPoint(timestamp: Date(timeIntervalSince1970: 120), value: 13, unit: .celsius),
            MetricHistoryPoint(timestamp: Date(timeIntervalSince1970: 130), value: 14, unit: .celsius)
        ]

        let continuityKeys = ChartSeriesPipeline.continuityKeys(
            for: samples,
            seriesKey: "temperature.sensor-1",
            timestamp: \.timestamp
        )

        XCTAssertEqual(
            continuityKeys,
            [
                "temperature.sensor-1#0",
                "temperature.sensor-1#0",
                "temperature.sensor-1#0",
                "temperature.sensor-1#1",
                "temperature.sensor-1#1"
            ]
        )
    }

    func testContinuityKeysStayContinuousAtRegularCadence() {
        let samples = [
            MetricHistoryPoint(timestamp: Date(timeIntervalSince1970: 0), value: 10, unit: .celsius),
            MetricHistoryPoint(timestamp: Date(timeIntervalSince1970: 10), value: 11, unit: .celsius),
            MetricHistoryPoint(timestamp: Date(timeIntervalSince1970: 20), value: 12, unit: .celsius),
            MetricHistoryPoint(timestamp: Date(timeIntervalSince1970: 30), value: 13, unit: .celsius)
        ]

        let continuityKeys = ChartSeriesPipeline.continuityKeys(
            for: samples,
            seriesKey: "temperature.sensor-1",
            timestamp: \.timestamp
        )

        XCTAssertEqual(
            continuityKeys,
            [
                "temperature.sensor-1#0",
                "temperature.sensor-1#0",
                "temperature.sensor-1#0",
                "temperature.sensor-1#0"
            ]
        )
    }

    func testHorizontalDetachedZoomIgnoresVerticalDistance() {
        let decision = DetachedChartInteractionOverlay.zoomDecision(
            horizontalDistance: 48,
            verticalDistance: 96,
            zoomMode: .horizontal
        )

        XCTAssertTrue(decision.shouldZoomX)
        XCTAssertFalse(decision.shouldZoomY)
    }

    func testHorizontalDetachedZoomSelectionSpansPlotHeight() {
        let plotFrame = CGRect(x: 20, y: 30, width: 300, height: 180)
        let rect = DetachedChartInteractionOverlay.selectionRect(
            for: CGPoint(x: 80, y: 60),
            current: CGPoint(x: 180, y: 140),
            plotFrame: plotFrame,
            zoomMode: .horizontal
        )

        XCTAssertEqual(rect.minX, 80)
        XCTAssertEqual(rect.width, 100)
        XCTAssertEqual(rect.minY, plotFrame.minY)
        XCTAssertEqual(rect.height, plotFrame.height)
    }

    private func makePoint(
        timestamp: Date,
        value: Double,
        seriesKey: String,
        seriesLabel: String,
        continuityKey: String,
        color: Color = .cyan
    ) -> TimeSeriesChartPoint {
        TimeSeriesChartPoint(
            timestamp: timestamp,
            value: value,
            seriesKey: seriesKey,
            seriesLabel: seriesLabel,
            continuityKey: continuityKey,
            color: color
        )
    }
}
