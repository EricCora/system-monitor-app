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

    func testComputePanelFrameUsesContentHeightNotParentHeight() {
        let parentFrame = NSRect(x: 760, y: 240, width: 520, height: 900)
        let visibleFrame = NSRect(x: 0, y: 0, width: 1728, height: 1117)

        let frame = DetachedMetricsPaneController.computePanelFrame(
            parentFrame: parentFrame,
            visibleFrame: visibleFrame,
            target: .cpu(chart: .usage)
        )

        let expectedHeight = DetachedMetricsPaneController.contentHeight(for: .cpu(chart: .usage))
        XCTAssertEqual(frame.height, expectedHeight, accuracy: 0.5)
        XCTAssertNotEqual(frame.height, parentFrame.height - 8, accuracy: 0.5)
        XCTAssertEqual(frame.maxY, parentFrame.maxY, accuracy: 0.5)
    }

    func testContentHeightRespectsMinimumAndMaximumBounds() {
        let standard = DetachedMetricsPaneController.contentHeight(for: .memory(chart: .pressure))
        XCTAssertGreaterThanOrEqual(standard, DetachedPaneLayout.minimumPanelHeight)
        XCTAssertLessThanOrEqual(standard, DetachedPaneLayout.maximumPanelHeight)

        let compare = DetachedMetricsPaneController.contentHeight(for: .temperatureCompare)
        XCTAssertGreaterThanOrEqual(compare, DetachedPaneLayout.minimumPanelHeight)
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

    func testTemperatureCompareTargetRoutesToTemperatureFamily() {
        XCTAssertEqual(DetachedMetricsPaneTarget.temperatureCompare.family, .temperature)
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

    func testAppDeactivateHidesPanelWithoutClearingPinnedTarget() {
        let controller = DetachedMetricsPaneController()
        controller.setPinnedTargetForTesting(.cpu(chart: .usage))
        controller.setPreviewTargetForTesting(.cpu(chart: .loadAverage))

        controller.closePanel(clearSelection: false)

        XCTAssertEqual(controller.pinnedTarget, .cpu(chart: .usage))
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

    @MainActor
    func testPinningFromCPUPreviewRestoresSavedHistoryWindow() async throws {
        let defaults = makeDefaults()

        try await withUniqueTemporaryDirectory { temporaryRoot in
            let coordinator = AppCoordinator(
                defaults: defaults,
                metricHistoryDatabaseURL: temporaryRoot.appendingPathComponent("metric-history.sqlite"),
                memoryHistoryDatabaseURL: temporaryRoot.appendingPathComponent("memory-history.sqlite3"),
                temperatureHistoryDatabaseURL: temporaryRoot.appendingPathComponent("temperature-history.sqlite3")
            )
            coordinator.selectedCPUHistoryWindow = .oneHour
            coordinator.compactCPUChartWindow = .sixHours
            let controller = DetachedMetricsPaneController()
            let parentWindow = NSWindow(
                contentRect: NSRect(x: 200, y: 200, width: 400, height: 300),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )

            controller.preview(.cpu(chart: .usage), coordinator: coordinator, parentWindow: parentWindow)
            XCTAssertEqual(coordinator.selectedCPUHistoryWindow, .sixHours)

            controller.pin(.cpu(chart: .usage), coordinator: coordinator, parentWindow: parentWindow)
            XCTAssertEqual(coordinator.selectedCPUHistoryWindow, .sixHours)

            controller.unpin()
            XCTAssertEqual(coordinator.selectedCPUHistoryWindow, .oneHour)

            await coordinator.shutdown()
        }
    }

    @MainActor
    func testCPUPreviewMirrorsCompactChartWindowAndRestoresOnDismiss() async throws {
        let defaults = makeDefaults()

        try await withUniqueTemporaryDirectory { temporaryRoot in
            let coordinator = AppCoordinator(
                defaults: defaults,
                metricHistoryDatabaseURL: temporaryRoot.appendingPathComponent("metric-history.sqlite"),
                memoryHistoryDatabaseURL: temporaryRoot.appendingPathComponent("memory-history.sqlite3"),
                temperatureHistoryDatabaseURL: temporaryRoot.appendingPathComponent("temperature-history.sqlite3")
            )
            coordinator.selectedCPUHistoryWindow = .oneHour
            coordinator.compactCPUChartWindow = .sixHours
            let controller = DetachedMetricsPaneController()
            let parentWindow = NSWindow(
                contentRect: NSRect(x: 200, y: 200, width: 400, height: 300),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )

            controller.preview(.cpu(chart: .usage), coordinator: coordinator, parentWindow: parentWindow)
            XCTAssertEqual(coordinator.selectedCPUHistoryWindow, .sixHours)

            controller.clearPreview(.cpu(chart: .usage))
            controller.setMainListHovering(false)
            controller.setPanelHovering(false)

            try await Task.sleep(nanoseconds: 260_000_000)
            XCTAssertEqual(coordinator.selectedCPUHistoryWindow, .oneHour)

            await coordinator.shutdown()
        }
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "DetachedMetricsPaneControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func withUniqueTemporaryDirectory(
        _ body: (URL) async throws -> Void
    ) async throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)

        let previousTMPDIR = getenv("TMPDIR").flatMap { pointer in
            String(validatingUTF8: pointer)
        }
        setenv("TMPDIR", temporaryRoot.path + "/", 1)
        defer {
            if let previousTMPDIR {
                setenv("TMPDIR", previousTMPDIR, 1)
            } else {
                unsetenv("TMPDIR")
            }
            try? fileManager.removeItem(at: temporaryRoot)
        }

        try await body(temporaryRoot)
    }
}
