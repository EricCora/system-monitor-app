import XCTest
@testable import PulseBarApp
import PulseBarCore

final class ChartRenderSemanticsTests: XCTestCase {
    func testStackedAreaSplitsOnTimelineGap() {
        let points = [
            makePoint(seriesKey: "cpu.user", continuityKey: "cpu.user#0", timestamp: 0),
            makePoint(seriesKey: "cpu.system", continuityKey: "cpu.system#0", timestamp: 0),
            makePoint(seriesKey: "cpu.user", continuityKey: "cpu.user#0", timestamp: 10),
            makePoint(seriesKey: "cpu.user", continuityKey: "cpu.user#0", timestamp: 20),
            makePoint(seriesKey: "cpu.user", continuityKey: "cpu.user#1", timestamp: 120)
        ]
        let segments = ChartRenderSemantics.continuitySegments(for: .stackedArea, points: points)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].count, 4)
        XCTAssertEqual(segments[1].count, 1)
    }

    func testStackedAreaKeepsSeriesTogetherWithinSegment() {
        let points = [
            makePoint(seriesKey: "a", continuityKey: "a#0", timestamp: 1),
            makePoint(seriesKey: "b", continuityKey: "b#0", timestamp: 1),
            makePoint(seriesKey: "a", continuityKey: "a#0", timestamp: 2)
        ]
        let segments = ChartRenderSemantics.continuitySegments(for: .stackedArea, points: points)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].count, 3)
    }

    func testLineStyleUsesContinuitySegments() {
        let points = [
            makePoint(seriesKey: "a", continuityKey: "a#0", timestamp: 1),
            makePoint(seriesKey: "a", continuityKey: "a#1", timestamp: 2)
        ]
        let segments = ChartRenderSemantics.continuitySegments(for: .lineOnly, points: points)
        XCTAssertEqual(segments.count, 2)
    }

    func testChartSeriesIdentityUsesContinuityKey() {
        let point = makePoint(seriesKey: "cpu.user", continuityKey: "cpu.user#3", timestamp: 10)
        XCTAssertEqual(ChartRenderSemantics.chartSeriesIdentity(for: point), "cpu.user#3")
    }

    func testMemoryLayerRanksStackBottomToTop() {
        XCTAssertLessThan(ChartRenderSemantics.layerRank(for: "memory.wired"), ChartRenderSemantics.layerRank(for: "memory.active"))
        XCTAssertLessThan(ChartRenderSemantics.layerRank(for: "memory.active"), ChartRenderSemantics.layerRank(for: "memory.compressed"))
        XCTAssertLessThan(ChartRenderSemantics.layerRank(for: "memory.compressed"), ChartRenderSemantics.layerRank(for: "memory.free"))
    }

    func testStackedMemorySegmentsPreserveLayerOrderAtTimestamp() {
        let timestamp = Date(timeIntervalSince1970: 100)
        let points = [
            makePoint(seriesKey: "memory.free", continuityKey: "memory.free#0", timestamp: timestamp.timeIntervalSince1970, value: 40),
            makePoint(seriesKey: "memory.wired", continuityKey: "memory.wired#0", timestamp: timestamp.timeIntervalSince1970, value: 20),
            makePoint(seriesKey: "memory.active", continuityKey: "memory.active#0", timestamp: timestamp.timeIntervalSince1970, value: 25),
            makePoint(seriesKey: "memory.compressed", continuityKey: "memory.compressed#0", timestamp: timestamp.timeIntervalSince1970, value: 15)
        ]
        let groups = ChartRenderSemantics.renderGroups(for: .stackedArea, points: points)
        XCTAssertEqual(groups.first?.segments.first?.map(\.seriesKey), [
            "memory.wired", "memory.active", "memory.compressed", "memory.free"
        ])
    }

    func testBaselineRenderGroupsUseStableSeriesLayerOrder() {
        let points = [
            makePoint(seriesKey: "load.1", continuityKey: "load.1#0", timestamp: 0),
            makePoint(seriesKey: "load.5", continuityKey: "load.5#0", timestamp: 0),
            makePoint(seriesKey: "load.15", continuityKey: "load.15#0", timestamp: 0),
            makePoint(seriesKey: "load.1", continuityKey: "load.1#1", timestamp: 120)
        ]
        let groups = ChartRenderSemantics.renderGroups(for: .baselineAreaLine, points: points)
        XCTAssertEqual(groups.map(\.id), ["load.15", "load.5", "load.1"])
        XCTAssertEqual(groups[2].segments.count, 2)
    }

    private func makePoint(seriesKey: String, continuityKey: String, timestamp: TimeInterval, value: Double = 1) -> TimeSeriesChartPoint {
        TimeSeriesChartPoint(
            timestamp: Date(timeIntervalSince1970: timestamp),
            value: value,
            seriesKey: seriesKey,
            seriesLabel: seriesKey,
            continuityKey: continuityKey,
            color: .red
        )
    }
}
