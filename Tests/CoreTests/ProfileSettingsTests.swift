import XCTest
@testable import PulseBarCore

final class ProfileSettingsTests: XCTestCase {
    func testMigrationCreatesCustomActiveProfile() {
        let legacy = LegacySettingsSnapshot(
            sampleInterval: 3,
            showCPUInMenu: true,
            showMemoryInMenu: true,
            showNetworkInMenu: false,
            showDiskInMenu: false,
            showTemperatureInMenu: true,
            throughputUnit: .bitsPerSecond,
            selectedWindow: .fifteenMinutes,
            cpuAlertEnabled: true,
            cpuAlertThreshold: 88,
            cpuAlertDuration: 40,
            temperatureAlertEnabled: true,
            temperatureAlertThreshold: 95,
            temperatureAlertDuration: 25
        )

        let settings = AppSettingsV2.migrated(from: legacy)

        XCTAssertEqual(settings.activeProfile, .custom)
        XCTAssertEqual(settings.customProfile.sampleInterval, 3)
        XCTAssertEqual(settings.customProfile.throughputUnit, .bitsPerSecond)
        XCTAssertEqual(settings.customProfile.temperatureAlertThreshold, 95)
        XCTAssertFalse(settings.autoSwitchRules.isEnabled)
    }

    func testBuiltInProfileResolution() {
        let settings = AppSettingsV2(
            activeProfile: .balanced,
            customProfile: .quiet,
            autoSwitchRules: .defaults,
            privilegedTemperatureEnabled: false
        )

        XCTAssertEqual(settings.settings(for: .quiet), .quiet)
        XCTAssertEqual(settings.settings(for: .balanced), .balanced)
        XCTAssertEqual(settings.settings(for: .performance), .performance)
    }
}
