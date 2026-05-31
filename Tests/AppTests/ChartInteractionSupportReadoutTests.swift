import XCTest
@testable import PulseBarApp
import PulseBarCore

final class ChartInteractionSupportReadoutTests: XCTestCase {
    func testAnchorTimestampUsesLatestWhenNotHovering() {
        let base = Date(timeIntervalSince1970: 10_000)
        let points = [
            makePoint(timestamp: base, seriesKey: "cpu.user", value: 10),
            makePoint(timestamp: base.addingTimeInterval(30), seriesKey: "cpu.user", value: 20),
            makePoint(timestamp: base.addingTimeInterval(30), seriesKey: "cpu.system", value: 5)
        ]

        let anchor = ChartInteractionSupport.anchorTimestamp(in: points, hoveredDate: nil)
        XCTAssertEqual(anchor, base.addingTimeInterval(30))
    }

    func testAnchorTimestampUsesNearestSharedTimestampWhenHovering() {
        let base = Date(timeIntervalSince1970: 20_000)
        let points = [
            makePoint(timestamp: base, seriesKey: "cpu.user", value: 10),
            makePoint(timestamp: base, seriesKey: "cpu.system", value: 5),
            makePoint(timestamp: base.addingTimeInterval(60), seriesKey: "cpu.user", value: 30),
            makePoint(timestamp: base.addingTimeInterval(60), seriesKey: "cpu.system", value: 15)
        ]
        let hover = base.addingTimeInterval(55)

        let anchor = ChartInteractionSupport.anchorTimestamp(in: points, hoveredDate: hover)
        XCTAssertEqual(anchor, base.addingTimeInterval(60))
    }

    func testPreparedReadoutAlignsMultiSeriesAtAnchor() {
        let base = Date(timeIntervalSince1970: 30_000)
        let user = [
            MetricHistoryPoint(timestamp: base, value: 30, unit: .percent),
            MetricHistoryPoint(timestamp: base.addingTimeInterval(30), value: 40, unit: .percent)
        ]
        let system = [
            MetricHistoryPoint(timestamp: base, value: 20, unit: .percent),
            MetricHistoryPoint(timestamp: base.addingTimeInterval(30), value: 25, unit: .percent)
        ]
        let model = PreparedTimeSeriesChartModel.fromCPUUsage(
            userHistory: user,
            systemHistory: system,
            smoothingAlpha: 1.0
        )

        let readout = ChartInteractionSupport.preparedReadout(in: model.points, hoveredDate: nil)
        XCTAssertEqual(readout?.timestamp, base.addingTimeInterval(30))
        XCTAssertEqual(readout?.value(forSeriesKey: "cpu.user") ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(readout?.value(forSeriesKey: "cpu.system") ?? -1, 25, accuracy: 0.001)
    }

    func testPreparedReadoutMatchesChartValuesOnHoverNotRawHistory() {
        let base = Date(timeIntervalSince1970: 40_000)
        let user = [
            MetricHistoryPoint(timestamp: base, value: 10, unit: .percent),
            MetricHistoryPoint(timestamp: base.addingTimeInterval(30), value: 90, unit: .percent)
        ]
        let system = [
            MetricHistoryPoint(timestamp: base.addingTimeInterval(5), value: 5, unit: .percent),
            MetricHistoryPoint(timestamp: base.addingTimeInterval(35), value: 8, unit: .percent)
        ]
        let model = PreparedTimeSeriesChartModel.fromCPUUsage(
            userHistory: user,
            systemHistory: system,
            window: .sixHours,
            smoothingAlpha: 1.0
        )
        let anchor = ChartInteractionSupport.anchorTimestamp(in: model.points, hoveredDate: base.addingTimeInterval(32))
        let readout = ChartInteractionSupport.preparedReadout(in: model.points, hoveredDate: base.addingTimeInterval(32))

        XCTAssertEqual(readout?.timestamp, anchor)
        let chartUser = model.points.first { $0.seriesKey == "cpu.user" && $0.timestamp == anchor }?.value
        let chartSystem = model.points.first { $0.seriesKey == "cpu.system" && $0.timestamp == anchor }?.value
        XCTAssertEqual(readout?.value(forSeriesKey: "cpu.user"), chartUser)
        XCTAssertEqual(readout?.value(forSeriesKey: "cpu.system"), chartSystem)

        let rawUser = ChartInteractionSupport.nearestPoint(in: user, hoveredDate: base.addingTimeInterval(32))?.value
        let rawSystem = ChartInteractionSupport.nearestPoint(in: system, hoveredDate: base.addingTimeInterval(32))?.value
        if rawUser != chartUser || rawSystem != chartSystem {
            XCTAssertNotEqual(readout?.value(forSeriesKey: "cpu.user"), rawUser)
        }
    }

    func testReadoutHandlesMisalignedSeriesWithoutFalseZeroes() {
        let base = Date(timeIntervalSince1970: 60_000)
        let points = [
            makePoint(timestamp: base, seriesKey: "load.1", value: 1.2),
            makePoint(timestamp: base.addingTimeInterval(5), seriesKey: "load.5", value: 2.4),
            makePoint(timestamp: base.addingTimeInterval(10), seriesKey: "load.15", value: 3.6)
        ]
        let hover = base.addingTimeInterval(6)

        let readout = ChartInteractionSupport.preparedReadout(in: points, hoveredDate: hover)
        XCTAssertEqual(readout?.value(forSeriesKey: "load.1"), 1.2)
        XCTAssertEqual(readout?.value(forSeriesKey: "load.5"), 2.4)
        XCTAssertEqual(readout?.value(forSeriesKey: "load.15"), 3.6)
        XCTAssertNotEqual(readout?.value(forSeriesKey: "load.5"), 0)
        XCTAssertNotEqual(readout?.value(forSeriesKey: "load.15"), 0)
    }

    func testAnchorTimestampTieBreaksDeterministically() {
        let base = Date(timeIntervalSince1970: 70_000)
        let points = [
            makePoint(timestamp: base, seriesKey: "load.1", value: 1),
            makePoint(timestamp: base.addingTimeInterval(10), seriesKey: "load.5", value: 2)
        ]
        let hover = base.addingTimeInterval(5)

        let anchor = ChartInteractionSupport.anchorTimestamp(in: points, hoveredDate: hover)
        XCTAssertEqual(anchor, base.addingTimeInterval(10))
    }

    func testCPUPaneReadoutHeaderLegendAndSummaryStayInSync() {
        let base = Date(timeIntervalSince1970: 50_000)
        let user = [
            MetricHistoryPoint(timestamp: base, value: 12, unit: .percent),
            MetricHistoryPoint(timestamp: base.addingTimeInterval(30), value: 22, unit: .percent)
        ]
        let system = [
            MetricHistoryPoint(timestamp: base, value: 8, unit: .percent),
            MetricHistoryPoint(timestamp: base.addingTimeInterval(30), value: 18, unit: .percent)
        ]
        let model = PreparedTimeSeriesChartModel.fromCPUUsage(
            userHistory: user,
            systemHistory: system,
            smoothingAlpha: 1.0
        )
        let readout = ChartInteractionSupport.preparedReadout(in: model.points, hoveredDate: nil)
        let userValue = readout?.value(forSeriesKey: "cpu.user") ?? 0
        let systemValue = readout?.value(forSeriesKey: "cpu.system") ?? 0
        let headerTotal = userValue + systemValue
        let legendUser = readout?.value(forSeriesKey: "cpu.user")
        let legendSystem = readout?.value(forSeriesKey: "cpu.system")
        let summaryIdle = max(0, 100 - userValue - systemValue)

        XCTAssertEqual(headerTotal, 40, accuracy: 0.001)
        XCTAssertEqual(legendUser ?? -1, 22, accuracy: 0.001)
        XCTAssertEqual(legendSystem ?? -1, 18, accuracy: 0.001)
        XCTAssertEqual(summaryIdle, 60, accuracy: 0.001)
    }

    private func makePoint(timestamp: Date, seriesKey: String, value: Double) -> TimeSeriesChartPoint {
        TimeSeriesChartPoint(
            timestamp: timestamp,
            value: value,
            seriesKey: seriesKey,
            seriesLabel: seriesKey,
            continuityKey: "\(seriesKey).0",
            color: .cyan
        )
    }
}
