import XCTest
@testable import PulseBarApp
import PulseBarCore

@MainActor
final class SettingsControllerWindowTests: XCTestCase {
    func testPerSurfaceChartWindowsPersistIndependently() {
        let defaults = makeDefaults()

        do {
            let controller = SettingsController(defaults: defaults)
            controller.compactCPUChartWindow = .sixHours
            controller.batteryChartWindow = .oneDay
            controller.networkChartWindow = .oneWeek
            controller.diskChartWindow = .oneMonth
            controller.selectedCPUHistoryWindow = .fifteenMinutes
            controller.selectedMemoryHistoryWindow = .oneHour
            controller.selectedTemperatureHistoryWindow = .sixHours
        }

        let restored = SettingsController(defaults: defaults)

        XCTAssertEqual(restored.compactCPUChartWindow, .sixHours)
        XCTAssertEqual(restored.batteryChartWindow, .oneDay)
        XCTAssertEqual(restored.networkChartWindow, .oneWeek)
        XCTAssertEqual(restored.diskChartWindow, .oneMonth)
        XCTAssertEqual(restored.selectedCPUHistoryWindow, .fifteenMinutes)
        XCTAssertEqual(restored.selectedMemoryHistoryWindow, .oneHour)
        XCTAssertEqual(restored.selectedTemperatureHistoryWindow, .sixHours)
    }

    func testVisibleChartWindowsNormalizeOrderAndFallbackWhenEmpty() {
        let defaults = makeDefaults()
        let controller = SettingsController(defaults: defaults)

        controller.visibleChartWindows = [.oneMonth, .fifteenMinutes, .oneHour]
        XCTAssertEqual(controller.effectiveVisibleChartWindows, [.fifteenMinutes, .oneHour, .oneMonth])

        controller.visibleChartWindows = []
        XCTAssertEqual(controller.effectiveVisibleChartWindows, ChartWindow.allCases)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "SettingsControllerWindowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
