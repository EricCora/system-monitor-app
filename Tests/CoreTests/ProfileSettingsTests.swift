import XCTest
@testable import PulseBarCore

final class ProfileSettingsTests: XCTestCase {
    func testMigrationCreatesCustomActiveProfile() {
        let legacy = LegacySettingsSnapshot(
            sampleInterval: 3,
            showCPUInMenu: true,
            showMemoryInMenu: true,
            showBatteryInMenu: false,
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
            temperatureAlertDuration: 25,
            memoryPressureAlertEnabled: true,
            memoryPressureAlertThreshold: 93,
            memoryPressureAlertDuration: 35,
            diskFreeAlertEnabled: true,
            diskFreeAlertThresholdBytes: 15 * 1_073_741_824,
            diskFreeAlertDuration: 45
        )

        let settings = AppSettingsV2.migrated(from: legacy)

        XCTAssertEqual(settings.activeProfile, .custom)
        XCTAssertEqual(settings.customProfile.sampleInterval, 3)
        XCTAssertEqual(settings.customProfile.throughputUnit, .bitsPerSecond)
        XCTAssertEqual(settings.customProfile.temperatureAlertThreshold, 95)
        XCTAssertEqual(settings.customProfile.memoryPressureAlertThreshold, 93)
        XCTAssertEqual(settings.customProfile.diskFreeAlertDuration, 45)
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

    func testDecodingLegacyProfileSettingsBackfillsNewFields() throws {
        let legacyJSON = """
        {
          "sampleInterval": 2,
          "showCPUInMenu": true,
          "showMemoryInMenu": true,
          "showNetworkInMenu": true,
          "showDiskInMenu": false,
          "showTemperatureInMenu": true,
          "throughputUnit": "bytesPerSecond",
          "selectedWindow": "oneHour",
          "cpuAlertEnabled": false,
          "cpuAlertThreshold": 85,
          "cpuAlertDuration": 30,
          "temperatureAlertEnabled": false,
          "temperatureAlertThreshold": 92,
          "temperatureAlertDuration": 20
        }
        """

        let decoded = try JSONDecoder().decode(ProfileSettings.self, from: Data(legacyJSON.utf8))
        XCTAssertFalse(decoded.showBatteryInMenu)
        XCTAssertFalse(decoded.memoryPressureAlertEnabled)
        XCTAssertEqual(decoded.memoryPressureAlertThreshold, 90)
        XCTAssertEqual(decoded.memoryPressureAlertDuration, 30)
        XCTAssertFalse(decoded.diskFreeAlertEnabled)
        XCTAssertEqual(decoded.diskFreeAlertDuration, 30)
        XCTAssertEqual(decoded.diskFreeAlertThresholdBytes, 20 * 1_073_741_824)
    }
}
