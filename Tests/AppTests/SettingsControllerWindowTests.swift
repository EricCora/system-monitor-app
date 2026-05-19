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

    func testPrivilegedTemperatureDefaultsEnabledForFreshInstall() {
        let defaults = makeDefaults()

        let controller = SettingsController(defaults: defaults)

        XCTAssertTrue(controller.privilegedTemperatureEnabled)
    }

    func testStoredLegacySettingsWithoutExplicitPreferenceFallbackToEnabled() throws {
        let defaults = makeDefaults()
        let legacy = AppSettingsV4(
            globalSamplingInterval: 2,
            activeProfile: .balanced,
            customProfile: .balanced,
            autoSwitchRules: .defaults,
            privilegedTemperatureEnabled: false
        )
        defaults.set(try JSONEncoder().encode(legacy), forKey: "settings.v4.data")

        let controller = SettingsController(defaults: defaults)

        XCTAssertTrue(controller.privilegedTemperatureEnabled)
    }

    func testVisibleChartWindowsNormalizeOrderAndFallbackWhenEmpty() {
        let defaults = makeDefaults()
        let controller = SettingsController(defaults: defaults)

        controller.visibleChartWindows = [.oneMonth, .fifteenMinutes, .oneHour]
        XCTAssertEqual(controller.effectiveVisibleChartWindows, [.fifteenMinutes, .oneHour, .oneMonth])

        controller.visibleChartWindows = []
        XCTAssertEqual(controller.effectiveVisibleChartWindows, ChartWindow.allCases)
    }

    func testDashboardPreferencesPersistAcrossRestarts() {
        let defaults = makeDefaults()

        do {
            let controller = SettingsController(defaults: defaults)
            controller.dashboardCardOrder = [.network, .cpu, .memory, .battery, .disk, .sensors]
            controller.chartMinorGridEnabled = true
            controller.chartSmoothingAlpha = 0.35
            controller.dashboardLayout = .compactMatrix
            controller.dashboardDensity = .comfortable
            controller.dashboardCardSize = .expanded
            controller.setDashboardCard(.battery, isVisible: false)
            controller.menuBarDisplayMode = .dense
            controller.setMenuBarMetricStyle(.iconText, for: .cpu)
            controller.favoriteSensorIDs = ["cpu", "gpu"]
            controller.saveSensorPreset(name: "Travel", sensorIDs: ["cpu", "gpu"])
        }

        let restored = SettingsController(defaults: defaults)

        XCTAssertEqual(restored.dashboardCardOrder, [.network, .cpu, .memory, .battery, .disk, .sensors])
        XCTAssertTrue(restored.chartMinorGridEnabled)
        XCTAssertEqual(restored.chartSmoothingAlpha, 0.35, accuracy: 0.001)
        XCTAssertEqual(restored.dashboardLayout, .compactMatrix)
        XCTAssertEqual(restored.dashboardDensity, .comfortable)
        XCTAssertEqual(restored.dashboardCardSize, .expanded)
        XCTAssertEqual(restored.dashboardCardVisibility[.battery], false)
        XCTAssertEqual(restored.dashboardCardVisibility[.cpu], true)
        XCTAssertEqual(restored.menuBarDisplayMode, .dense)
        XCTAssertEqual(restored.menuBarMetricStyle(for: .cpu), .iconText)
        XCTAssertEqual(restored.favoriteSensorIDs, ["cpu", "gpu"])
        XCTAssertEqual(restored.sensorPresets.map(\.name), ["Travel"])
        XCTAssertEqual(restored.sensorPresets.first?.sensorIDs, ["cpu", "gpu"])
    }

    func testDashboardPreferencesMigrateFromV3Defaults() throws {
        let defaults = makeDefaults()
        let legacy = AppSettingsV3(
            globalSamplingInterval: 2,
            activeProfile: .balanced,
            customProfile: .balanced,
            autoSwitchRules: .defaults,
            privilegedTemperatureEnabled: true
        )
        defaults.set(try JSONEncoder().encode(legacy), forKey: "settings.v3.data")

        let restored = SettingsController(defaults: defaults)

        XCTAssertEqual(restored.dashboardLayout, .cardDashboard)
        XCTAssertFalse(restored.chartMinorGridEnabled)
        XCTAssertEqual(restored.chartSmoothingAlpha, 1.0, accuracy: 0.001)
        XCTAssertEqual(restored.dashboardDensity, .compact)
        XCTAssertEqual(restored.dashboardCardSize, .standard)
        XCTAssertEqual(restored.dashboardCardOrder, DashboardCardID.defaultOrder)
        XCTAssertEqual(restored.dashboardCardVisibility, DashboardCardID.defaultVisibility)
        XCTAssertEqual(restored.menuBarDisplayMode, .compact)
        XCTAssertEqual(restored.favoriteSensorIDs, [])
        XCTAssertEqual(restored.sensorPresets, [])
    }

    func testDashboardCardVisibilityKeepsOneCardVisible() {
        let defaults = makeDefaults()

        let controller = SettingsController(defaults: defaults)
        for card in DashboardCardID.allCases {
            controller.setDashboardCard(card, isVisible: false)
        }

        let restored = SettingsController(defaults: defaults)

        XCTAssertEqual(restored.dashboardCardVisibility[.cpu], true)
        XCTAssertEqual(restored.dashboardCardVisibility.values.filter { $0 }.count, 1)
    }

    func testChartSmoothingAlphaNormalizesIntoSupportedRange() {
        let defaults = makeDefaults()

        do {
            let controller = SettingsController(defaults: defaults)
            controller.chartSmoothingAlpha = 0
            XCTAssertEqual(controller.chartSmoothingAlpha, 0.05, accuracy: 0.001)
            controller.chartSmoothingAlpha = 1.5
            XCTAssertEqual(controller.chartSmoothingAlpha, 1.0, accuracy: 0.001)
        }

        let restored = SettingsController(defaults: defaults)
        XCTAssertEqual(restored.chartSmoothingAlpha, 1.0, accuracy: 0.001)
    }

    func testLatestTemperatureSnapshotPersistsAcrossRestarts() {
        let defaults = makeDefaults()
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_321)
        let snapshot = LatestTemperatureSnapshot(
            channels: [
                SensorReading(
                    id: "cpu-die",
                    rawName: "CPU Die",
                    displayName: "CPU Die",
                    category: .cpu,
                    channelType: .temperatureCelsius,
                    value: 63,
                    source: "test",
                    timestamp: capturedAt
                )
            ],
            temperatureSensors: [
                TemperatureSensorReading(name: "CPU Die", celsius: 63)
            ],
            lastSuccessMessage: "Last successful privileged sample: 10:00 AM.",
            sourceDiagnostics: [],
            fanHealthy: false,
            channelsAvailable: [.temperatureCelsius],
            activeSourceChain: ["iohid"],
            fanParityGateBlocked: false,
            fanParityGateMessage: nil,
            capturedAt: capturedAt
        )

        do {
            let controller = SettingsController(defaults: defaults)
            controller.persistLatestTemperatureSnapshot(snapshot)
        }

        let restored = SettingsController(defaults: defaults)
        XCTAssertEqual(restored.loadLatestTemperatureSnapshot(), snapshot)

        restored.clearLatestTemperatureSnapshot()
        XCTAssertNil(restored.loadLatestTemperatureSnapshot())
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "SettingsControllerWindowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
