import XCTest
@testable import PulseBarCore

final class ProfileSettingsTests: XCTestCase {
    func testLegacyMigrationCreatesV3CustomProfileAndGlobalSamplingInterval() {
        let legacy = LegacySettingsSnapshot(
            sampleInterval: 3,
            showCPUInMenu: true,
            showMemoryInMenu: true,
            showBatteryInMenu: false,
            showNetworkInMenu: false,
            showDiskInMenu: false,
            showTemperatureInMenu: true,
            throughputUnit: .bitsPerSecond,
            chartAreaOpacity: 0.22,
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

        let settings = AppSettingsV3.migrated(from: legacy)

        XCTAssertEqual(settings.activeProfile, .custom)
        XCTAssertEqual(settings.globalSamplingInterval, 3)
        XCTAssertFalse(settings.liveCompositorFPSEnabled)
        XCTAssertEqual(settings.customProfile.throughputUnit, .bitsPerSecond)
        XCTAssertEqual(settings.customProfile.chartAreaOpacity, 0.22)
        XCTAssertEqual(settings.customProfile.temperatureAlertThreshold, 95)
        XCTAssertEqual(settings.customProfile.memoryPressureAlertThreshold, 93)
        XCTAssertEqual(settings.customProfile.diskFreeAlertDuration, 45)
        XCTAssertFalse(settings.autoSwitchRules.isEnabled)
    }

    func testV2MigrationUsesLegacySamplingIntervalOverride() {
        let settingsV2 = AppSettingsV2(
            activeProfile: .balanced,
            customProfile: .quiet,
            autoSwitchRules: .defaults,
            privilegedTemperatureEnabled: false
        )

        let migrated = AppSettingsV3.migrated(from: settingsV2, legacySamplingInterval: 1)

        XCTAssertEqual(migrated.globalSamplingInterval, 1)
        XCTAssertFalse(migrated.liveCompositorFPSEnabled)
        XCTAssertEqual(migrated.activeProfile, .balanced)
        XCTAssertEqual(migrated.settings(for: .balanced), .balanced)
    }

    func testBuiltInProfileResolution() {
        let settings = AppSettingsV3(
            globalSamplingInterval: 2,
            liveCompositorFPSEnabled: true,
            activeProfile: .balanced,
            customProfile: .quiet,
            autoSwitchRules: .defaults,
            privilegedTemperatureEnabled: false
        )

        XCTAssertEqual(settings.settings(for: .quiet), .quiet)
        XCTAssertEqual(settings.settings(for: .balanced), .balanced)
        XCTAssertEqual(settings.settings(for: .performance), .performance)
        XCTAssertTrue(settings.liveCompositorFPSEnabled)
    }

    func testDecodingV3WithoutLiveFPSFlagDefaultsToDisabled() throws {
        let json = """
        {
          "schemaVersion": 3,
          "globalSamplingInterval": 2,
          "activeProfile": "balanced",
          "customProfile": {
            "showCPUInMenu": true,
            "showMemoryInMenu": true,
            "showBatteryInMenu": false,
            "showNetworkInMenu": true,
            "showDiskInMenu": false,
            "showTemperatureInMenu": true,
            "throughputUnit": "bytesPerSecond",
            "chartAreaOpacity": 0.18,
            "cpuAlertEnabled": false,
            "cpuAlertThreshold": 85,
            "cpuAlertDuration": 30,
            "temperatureAlertEnabled": false,
            "temperatureAlertThreshold": 92,
            "temperatureAlertDuration": 20,
            "memoryPressureAlertEnabled": false,
            "memoryPressureAlertThreshold": 90,
            "memoryPressureAlertDuration": 30,
            "diskFreeAlertEnabled": false,
            "diskFreeAlertThresholdBytes": 21474836480,
            "diskFreeAlertDuration": 30
          },
          "autoSwitchRules": {
            "isEnabled": false,
            "acProfile": "balanced",
            "batteryProfile": "quiet"
          },
          "privilegedTemperatureEnabled": false
        }
        """

        let decoded = try JSONDecoder().decode(AppSettingsV3.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.liveCompositorFPSEnabled)
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
        XCTAssertEqual(decoded.chartAreaOpacity, 0.18)
        XCTAssertFalse(decoded.memoryPressureAlertEnabled)
        XCTAssertEqual(decoded.memoryPressureAlertThreshold, 90)
        XCTAssertEqual(decoded.memoryPressureAlertDuration, 30)
        XCTAssertFalse(decoded.diskFreeAlertEnabled)
        XCTAssertEqual(decoded.diskFreeAlertDuration, 30)
        XCTAssertEqual(decoded.diskFreeAlertThresholdBytes, 20 * 1_073_741_824)
    }
}
