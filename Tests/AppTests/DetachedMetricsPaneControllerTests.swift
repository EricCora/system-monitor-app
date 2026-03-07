import AppKit
import XCTest
@testable import PulseBarApp
import PulseBarCore

@MainActor
final class DetachedMetricsPaneControllerTests: XCTestCase {
    func testComputePanelFramePrefersLeftWhenSpaceIsAvailable() {
        let parentFrame = NSRect(x: 760, y: 240, width: 520, height: 500)
        let visibleFrame = NSRect(x: 0, y: 0, width: 1728, height: 1117)

        let frame = DetachedMetricsPaneController.computePanelFrame(
            parentFrame: parentFrame,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.maxX, parentFrame.minX - 4, accuracy: 0.5)
        XCTAssertEqual(frame.width, 560, accuracy: 0.5)
        XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX)
        XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX)
    }

    func testComputePanelFrameSwitchesToRightWhenLeftSpaceIsInsufficient() {
        let parentFrame = NSRect(x: 240, y: 200, width: 520, height: 500)
        let visibleFrame = NSRect(x: 0, y: 0, width: 1728, height: 1117)

        let frame = DetachedMetricsPaneController.computePanelFrame(
            parentFrame: parentFrame,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.minX, parentFrame.maxX + 4, accuracy: 0.5)
        XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX)
        XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX)
    }

    func testClearPreviewKeepsLastTargetUntilHideDelayFinishes() async {
        let controller = DetachedMetricsPaneController()

        controller.setMainListHovering(true)
        controller.setPreviewTargetForTesting(.temperature(sensorID: "cpu_die_5"))
        controller.clearPreview(.temperature(sensorID: "cpu_die_5"))

        XCTAssertEqual(controller.hoveredTarget, .temperature(sensorID: "cpu_die_5"))

        controller.setMainListHovering(false)

        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(controller.hoveredTarget, .temperature(sensorID: "cpu_die_5"))

        try? await Task.sleep(nanoseconds: 180_000_000)
        XCTAssertNil(controller.hoveredTarget)
    }

    func testInteractionLockPreventsHoverDismissUntilInteractionEnds() async {
        let controller = DetachedMetricsPaneController()

        controller.setMainListHovering(true)
        controller.setPreviewTargetForTesting(.cpu(chart: .loadAverage))
        controller.beginPaneInteraction()
        controller.clearPreview(.cpu(chart: .loadAverage))
        controller.setMainListHovering(false)
        controller.setPanelHovering(false)

        try? await Task.sleep(nanoseconds: 260_000_000)
        XCTAssertEqual(controller.hoveredTarget, .cpu(chart: .loadAverage))

        controller.endPaneInteraction()

        try? await Task.sleep(nanoseconds: 260_000_000)
        XCTAssertNil(controller.hoveredTarget)
    }
}
