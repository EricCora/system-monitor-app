import SwiftUI
import XCTest
@testable import PulseBarApp
import PulseBarCore

final class PreparedTimeSeriesChartModelTests: XCTestCase {
    func testMemoryCompositionProducesFourStackedSeriesPerTimestamp() {
        let history = [
            makeMemoryPoint(
                timestamp: Date(timeIntervalSince1970: 100),
                wired: 2_000,
                active: 3_000,
                compressed: 1_000,
                free: 4_000,
                total: 10_000
            ),
            makeMemoryPoint(
                timestamp: Date(timeIntervalSince1970: 200),
                wired: 1_000,
                active: 2_000,
                compressed: 500,
                free: 6_500,
                total: 10_000
            )
        ]

        let points = ChartSeriesPipeline.memoryCompositionPoints(history: history, smoothingAlpha: 1.0)

        XCTAssertEqual(Set(points.map(\.seriesKey)).count, 4)
        XCTAssertTrue(Set(points.map(\.seriesKey)).isSubset(of: [
            "memory.wired", "memory.active", "memory.compressed", "memory.free"
        ]))

        let atFirstTimestamp = points.filter { $0.timestamp == history[0].timestamp }
        let stackedSum = atFirstTimestamp.map(\.value).reduce(0, +)
        XCTAssertEqual(stackedSum, 100, accuracy: 0.01)

        let model = PreparedTimeSeriesChartModel.fromMemoryComposition(history: history)
        XCTAssertEqual(model.renderStyle, .stackedArea(fixedYDomain: 0 ... 100))
        XCTAssertEqual(model.sampleBudget, .fullChart)
        XCTAssertEqual(model.fixedYDomain, 0 ... 100)
        XCTAssertFalse(model.isEmpty)
    }

    func testMemoryCompositionSmoothingMovesValuesTowardPreviousSample() {
        let history = [
            makeMemoryPoint(
                timestamp: Date(timeIntervalSince1970: 100),
                wired: 0,
                active: 0,
                compressed: 0,
                free: 10_000,
                total: 10_000
            ),
            makeMemoryPoint(
                timestamp: Date(timeIntervalSince1970: 200),
                wired: 10_000,
                active: 0,
                compressed: 0,
                free: 0,
                total: 10_000
            )
        ]

        let unsmoothed = ChartSeriesPipeline.memoryCompositionPoints(history: history, smoothingAlpha: 1.0)
        let smoothed = ChartSeriesPipeline.memoryCompositionPoints(history: history, smoothingAlpha: 0.5)

        let unsmoothedWired = unsmoothed.filter { $0.seriesKey == "memory.wired" && $0.timestamp == history[1].timestamp }
        let smoothedWired = smoothed.filter { $0.seriesKey == "memory.wired" && $0.timestamp == history[1].timestamp }

        XCTAssertEqual(unsmoothedWired.first?.value ?? 0, 100, accuracy: 0.01)
        XCTAssertEqual(smoothedWired.first?.value ?? 0, 50, accuracy: 0.01)
    }

    func testPresentationIndexedPointsUseStableSeriesKeysNotMetricIDs() {
        let points = ChartSeriesPipeline.presentationIndexedPoints(
            values: [1, 5, 3, 9],
            key: "sparkline",
            label: "History",
            color: .cyan,
            maxPoints: 10
        )

        XCTAssertEqual(points.count, 4)
        XCTAssertTrue(points.allSatisfy { $0.seriesKey == "sparkline" })
        XCTAssertTrue(points.allSatisfy { $0.continuityKey.hasPrefix("sparkline.") })

        let model = PreparedTimeSeriesChartModel.fromSparklineValues([1, 2, 3, 4, 5])
        XCTAssertEqual(model.sampleBudget, .sparkline)
        XCTAssertEqual(model.miniPresentation, .indexedSparkline)
        XCTAssertFalse(model.isEmpty)
        XCTAssertGreaterThan(model.scale.yDomain.upperBound, model.scale.yDomain.lowerBound)
    }

    func testFromCPUUsageBuildsStackedUserAndSystemSeries() {
        let now = Date(timeIntervalSince1970: 1_000)
        let user = [
            MetricHistoryPoint(timestamp: now, value: 30, unit: .percent),
            MetricHistoryPoint(timestamp: now.addingTimeInterval(10), value: 40, unit: .percent)
        ]
        let system = [
            MetricHistoryPoint(timestamp: now, value: 20, unit: .percent),
            MetricHistoryPoint(timestamp: now.addingTimeInterval(10), value: 25, unit: .percent)
        ]

        let model = PreparedTimeSeriesChartModel.fromCPUUsage(userHistory: user, systemHistory: system)

        XCTAssertEqual(model.renderStyle, .stackedArea())
        XCTAssertEqual(model.sampleBudget, .fullChart)
        XCTAssertNil(model.miniPresentation)
        XCTAssertEqual(Set(model.points.map(\.seriesKey)), Set(["cpu.user", "cpu.system"]))
        XCTAssertEqual(model.fixedYDomain, 0 ... 100)
    }

    func testFromTemperatureCompareRequiresMultiplePointsPerSeries() {
        let early = Date(timeIntervalSince1970: 100)
        let late = Date(timeIntervalSince1970: 200)

        let sparse = PreparedTimeSeriesChartModel.fromTemperatureCompare(
            series: [
                ChartMetricSeriesDescriptor(
                    key: "a",
                    label: "A",
                    color: .red,
                    samples: [TemperatureHistoryPoint(sensorID: "a", timestamp: early, value: 50, channelType: .temperatureCelsius)]
                ),
                ChartMetricSeriesDescriptor(
                    key: "b",
                    label: "B",
                    color: .blue,
                    samples: [TemperatureHistoryPoint(sensorID: "b", timestamp: early, value: 55, channelType: .temperatureCelsius)]
                )
            ]
        )
        XCTAssertFalse(sparse.hasRenderableCompareHistory)

        let dense = PreparedTimeSeriesChartModel.fromTemperatureCompare(
            series: [
                ChartMetricSeriesDescriptor(
                    key: "a",
                    label: "A",
                    color: .red,
                    samples: [
                        TemperatureHistoryPoint(sensorID: "a", timestamp: early, value: 50, channelType: .temperatureCelsius),
                        TemperatureHistoryPoint(sensorID: "a", timestamp: late, value: 52, channelType: .temperatureCelsius)
                    ]
                )
            ]
        )
        XCTAssertTrue(dense.hasRenderableCompareHistory)
        XCTAssertEqual(dense.sampleBudget, .compareLine)
        XCTAssertEqual(dense.renderStyle, .lineOnly)
    }

    func testBidirectionalSparklineCarriesSeparateValueArrays() {
        let model = PreparedTimeSeriesChartModel.fromBidirectionalSparkline(
            positiveValues: [1, 2, 3],
            negativeValues: [4, 5]
        )

        XCTAssertEqual(model.positiveValues, [1, 2, 3])
        XCTAssertEqual(model.negativeValues, [4, 5])
        XCTAssertTrue(model.points.isEmpty)
        XCTAssertEqual(model.miniPresentation, .bidirectionalBars)
        XCTAssertEqual(model.sampleBudget, .bidirectionalBars)
    }

    func testChartSampleBudgetChangesPointCap() {
        XCTAssertGreaterThan(
            ChartSeriesPipeline.targetPointCount(for: .oneHour, budget: .fullChart),
            ChartSeriesPipeline.targetPointCount(for: .oneHour, budget: .compactChart)
        )
        XCTAssertEqual(ChartSeriesPipeline.targetPointCount(for: nil, budget: .sparkline), 36)
        XCTAssertEqual(ChartSeriesPipeline.targetPointCount(for: nil, budget: .menuBarBars), 18)
    }

    func testChartPlotGeometryBuildsNonEmptyPathsForValidSeries() {
        let points = [
            TimeSeriesChartPoint(
                timestamp: Date(timeIntervalSince1970: 100),
                value: 10,
                seriesKey: "a",
                seriesLabel: "A",
                continuityKey: "a#0",
                color: .cyan
            ),
            TimeSeriesChartPoint(
                timestamp: Date(timeIntervalSince1970: 200),
                value: 30,
                seriesKey: "a",
                seriesLabel: "A",
                continuityKey: "a#0",
                color: .cyan
            )
        ]
        let xDomain = Date(timeIntervalSince1970: 100)...Date(timeIntervalSince1970: 200)
        let yDomain = 0.0...40.0
        let size = CGSize(width: 200, height: 100)

        let segments = ChartPlotGeometry.groupedSegments(from: points)
        XCTAssertEqual(segments.count, 1)

        let area = ChartPlotGeometry.areaPath(
            points: points,
            baseline: 0,
            xDomain: xDomain,
            yDomain: yDomain,
            size: size
        )
        let line = ChartPlotGeometry.linePath(for: points, xDomain: xDomain, yDomain: yDomain, size: size)
        XCTAssertFalse(area.isEmpty)
        XCTAssertFalse(line.isEmpty)

        let indexedLine = ChartPlotGeometry.linePath(for: [10, 20, 15], size: size)
        XCTAssertFalse(indexedLine.isEmpty)
    }

    func testFromCPUSnapshotBuildsExpectedChartKinds() {
        let now = Date(timeIntervalSince1970: 1_000)
        let sample = MetricHistoryPoint(timestamp: now, value: 42, unit: .percent)
        let snapshot = CPUHistorySnapshot(
            user: [sample],
            system: [sample],
            idle: [sample],
            load1: [sample],
            load5: [sample],
            load15: [sample],
            gpuProcessor: [sample],
            gpuMemory: [sample],
            framesPerSecond: [sample]
        )

        XCTAssertEqual(PreparedTimeSeriesChartModel.fromCPU(snapshot: snapshot, chart: .usage, smoothingAlpha: 1).sampleBudget, .fullChart)
        XCTAssertEqual(PreparedTimeSeriesChartModel.fromCPU(snapshot: snapshot, chart: .loadAverage, smoothingAlpha: 1).renderStyle, .baselineAreaLine)
        XCTAssertFalse(PreparedTimeSeriesChartModel.fromCPU(snapshot: snapshot, chart: .gpu, smoothingAlpha: 1).isEmpty)
    }

    func testFromMemorySnapshotBuildsExpectedChartKinds() {
        let now = Date(timeIntervalSince1970: 1_000)
        let metric = MetricHistoryPoint(timestamp: now, value: 10, unit: .percent)
        let composition = makeMemoryPoint(
            timestamp: now,
            wired: 1_000,
            active: 2_000,
            compressed: 500,
            free: 6_500,
            total: 10_000
        )
        let snapshot = MemoryHistorySnapshot(
            composition: [composition],
            pressure: [metric],
            swap: [metric],
            pageIns: [metric],
            pageOuts: [metric]
        )

        XCTAssertEqual(
            PreparedTimeSeriesChartModel.fromMemory(snapshot: snapshot, chart: .composition, smoothingAlpha: 1).renderStyle,
            .stackedArea()
        )
        XCTAssertEqual(
            PreparedTimeSeriesChartModel.fromMemory(snapshot: snapshot, chart: .pressure, smoothingAlpha: 1).renderStyle,
            .baselineAreaLine
        )
    }

    func testDetachedPaneContentHeightMatchesLayoutFormula() {
        let target = DetachedMetricsPaneTarget.cpu(chart: .usage)
        let style = DetachedPaneLayout.paneStyle(for: target)
        let expected = DetachedPaneShellMetrics.chromeAboveChart
            + style.chartHeight
            + DetachedPaneShellMetrics.legendFooterBlockHeight
            + (DetachedPaneLayout.hostPadding * 2)
            + (DetachedPaneLayout.shellSurfacePadding * 2)

        XCTAssertEqual(DetachedPaneLayout.contentHeight(for: target), expected, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(expected, DetachedPaneLayout.minimumPanelHeight)
    }

    private func makeMemoryPoint(
        timestamp: Date,
        wired: Double,
        active: Double,
        compressed: Double,
        free: Double,
        total: Double
    ) -> MemoryHistoryPoint {
        MemoryHistoryPoint(
            timestamp: timestamp,
            appBytes: 0,
            wiredBytes: wired,
            activeBytes: active,
            compressedBytes: compressed,
            cacheBytes: 0,
            freeBytes: free,
            totalBytes: total,
            pressurePercent: 50
        )
    }
}
