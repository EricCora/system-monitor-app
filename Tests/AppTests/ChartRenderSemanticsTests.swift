import XCTest
@testable import PulseBarApp
import PulseBarCore

final class ChartRenderSemanticsTests: XCTestCase {
    func testStackedAreaGroupsBySeriesKey() {
        let points = [
            makePoint(seriesKey: "a", continuityKey: "gap#0", timestamp: 1),
            makePoint(seriesKey: "b", continuityKey: "gap#0", timestamp: 1),
            makePoint(seriesKey: "a", continuityKey: "gap#1", timestamp: 2)
        ]
        let segments = ChartRenderSemantics.continuitySegments(for: .stackedArea, points: points)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments.compactMap { $0.first?.seriesKey }.sorted(), ["a", "b"])
    }

    func testLineStyleUsesContinuitySegments() {
        let points = [
            makePoint(seriesKey: "a", continuityKey: "a#0", timestamp: 1),
            makePoint(seriesKey: "a", continuityKey: "a#1", timestamp: 2)
        ]
        let segments = ChartRenderSemantics.continuitySegments(for: .lineOnly, points: points)
        XCTAssertEqual(segments.count, 2)
    }

    private func makePoint(seriesKey: String, continuityKey: String, timestamp: TimeInterval) -> TimeSeriesChartPoint {
        TimeSeriesChartPoint(
            timestamp: Date(timeIntervalSince1970: timestamp),
            value: 1,
            seriesKey: seriesKey,
            seriesLabel: seriesKey,
            continuityKey: continuityKey,
            color: .red
        )
    }
}
