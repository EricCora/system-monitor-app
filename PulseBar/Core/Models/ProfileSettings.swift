import Foundation

public enum ProfileID: String, Codable, CaseIterable, Sendable {
    case quiet
    case balanced
    case performance
    case custom

    public var label: String {
        switch self {
        case .quiet:
            return "Quiet"
        case .balanced:
            return "Balanced"
        case .performance:
            return "Performance"
        case .custom:
            return "Custom"
        }
    }
}

public struct ProfileSettings: Codable, Sendable, Equatable {
    public var sampleInterval: Double
    public var showCPUInMenu: Bool
    public var showMemoryInMenu: Bool
    public var showNetworkInMenu: Bool
    public var showDiskInMenu: Bool
    public var showTemperatureInMenu: Bool
    public var throughputUnit: ThroughputDisplayUnit
    public var selectedWindow: TimeWindow

    public var cpuAlertEnabled: Bool
    public var cpuAlertThreshold: Double
    public var cpuAlertDuration: Int

    public var temperatureAlertEnabled: Bool
    public var temperatureAlertThreshold: Double
    public var temperatureAlertDuration: Int

    public init(
        sampleInterval: Double,
        showCPUInMenu: Bool,
        showMemoryInMenu: Bool,
        showNetworkInMenu: Bool,
        showDiskInMenu: Bool,
        showTemperatureInMenu: Bool,
        throughputUnit: ThroughputDisplayUnit,
        selectedWindow: TimeWindow,
        cpuAlertEnabled: Bool,
        cpuAlertThreshold: Double,
        cpuAlertDuration: Int,
        temperatureAlertEnabled: Bool,
        temperatureAlertThreshold: Double,
        temperatureAlertDuration: Int
    ) {
        self.sampleInterval = sampleInterval
        self.showCPUInMenu = showCPUInMenu
        self.showMemoryInMenu = showMemoryInMenu
        self.showNetworkInMenu = showNetworkInMenu
        self.showDiskInMenu = showDiskInMenu
        self.showTemperatureInMenu = showTemperatureInMenu
        self.throughputUnit = throughputUnit
        self.selectedWindow = selectedWindow
        self.cpuAlertEnabled = cpuAlertEnabled
        self.cpuAlertThreshold = cpuAlertThreshold
        self.cpuAlertDuration = cpuAlertDuration
        self.temperatureAlertEnabled = temperatureAlertEnabled
        self.temperatureAlertThreshold = temperatureAlertThreshold
        self.temperatureAlertDuration = temperatureAlertDuration
    }

    public static let quiet = ProfileSettings(
        sampleInterval: 5,
        showCPUInMenu: true,
        showMemoryInMenu: true,
        showNetworkInMenu: false,
        showDiskInMenu: false,
        showTemperatureInMenu: true,
        throughputUnit: .bytesPerSecond,
        selectedWindow: .fifteenMinutes,
        cpuAlertEnabled: false,
        cpuAlertThreshold: 90,
        cpuAlertDuration: 45,
        temperatureAlertEnabled: false,
        temperatureAlertThreshold: 95,
        temperatureAlertDuration: 30
    )

    public static let balanced = ProfileSettings(
        sampleInterval: 2,
        showCPUInMenu: true,
        showMemoryInMenu: true,
        showNetworkInMenu: true,
        showDiskInMenu: false,
        showTemperatureInMenu: true,
        throughputUnit: .bytesPerSecond,
        selectedWindow: .oneHour,
        cpuAlertEnabled: false,
        cpuAlertThreshold: 85,
        cpuAlertDuration: 30,
        temperatureAlertEnabled: false,
        temperatureAlertThreshold: 92,
        temperatureAlertDuration: 20
    )

    public static let performance = ProfileSettings(
        sampleInterval: 1,
        showCPUInMenu: true,
        showMemoryInMenu: true,
        showNetworkInMenu: true,
        showDiskInMenu: true,
        showTemperatureInMenu: true,
        throughputUnit: .bytesPerSecond,
        selectedWindow: .oneHour,
        cpuAlertEnabled: false,
        cpuAlertThreshold: 92,
        cpuAlertDuration: 20,
        temperatureAlertEnabled: false,
        temperatureAlertThreshold: 98,
        temperatureAlertDuration: 15
    )
}

public struct ProfileAutoSwitchRules: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var acProfile: ProfileID
    public var batteryProfile: ProfileID

    public init(isEnabled: Bool, acProfile: ProfileID, batteryProfile: ProfileID) {
        self.isEnabled = isEnabled
        self.acProfile = acProfile
        self.batteryProfile = batteryProfile
    }

    public static let defaults = ProfileAutoSwitchRules(
        isEnabled: false,
        acProfile: .balanced,
        batteryProfile: .quiet
    )
}

public struct LegacySettingsSnapshot: Sendable, Equatable {
    public var sampleInterval: Double
    public var showCPUInMenu: Bool
    public var showMemoryInMenu: Bool
    public var showNetworkInMenu: Bool
    public var showDiskInMenu: Bool
    public var showTemperatureInMenu: Bool
    public var throughputUnit: ThroughputDisplayUnit
    public var selectedWindow: TimeWindow

    public var cpuAlertEnabled: Bool
    public var cpuAlertThreshold: Double
    public var cpuAlertDuration: Int

    public var temperatureAlertEnabled: Bool
    public var temperatureAlertThreshold: Double
    public var temperatureAlertDuration: Int

    public init(
        sampleInterval: Double,
        showCPUInMenu: Bool,
        showMemoryInMenu: Bool,
        showNetworkInMenu: Bool,
        showDiskInMenu: Bool,
        showTemperatureInMenu: Bool,
        throughputUnit: ThroughputDisplayUnit,
        selectedWindow: TimeWindow,
        cpuAlertEnabled: Bool,
        cpuAlertThreshold: Double,
        cpuAlertDuration: Int,
        temperatureAlertEnabled: Bool,
        temperatureAlertThreshold: Double,
        temperatureAlertDuration: Int
    ) {
        self.sampleInterval = sampleInterval
        self.showCPUInMenu = showCPUInMenu
        self.showMemoryInMenu = showMemoryInMenu
        self.showNetworkInMenu = showNetworkInMenu
        self.showDiskInMenu = showDiskInMenu
        self.showTemperatureInMenu = showTemperatureInMenu
        self.throughputUnit = throughputUnit
        self.selectedWindow = selectedWindow
        self.cpuAlertEnabled = cpuAlertEnabled
        self.cpuAlertThreshold = cpuAlertThreshold
        self.cpuAlertDuration = cpuAlertDuration
        self.temperatureAlertEnabled = temperatureAlertEnabled
        self.temperatureAlertThreshold = temperatureAlertThreshold
        self.temperatureAlertDuration = temperatureAlertDuration
    }

    public func asProfileSettings() -> ProfileSettings {
        ProfileSettings(
            sampleInterval: sampleInterval,
            showCPUInMenu: showCPUInMenu,
            showMemoryInMenu: showMemoryInMenu,
            showNetworkInMenu: showNetworkInMenu,
            showDiskInMenu: showDiskInMenu,
            showTemperatureInMenu: showTemperatureInMenu,
            throughputUnit: throughputUnit,
            selectedWindow: selectedWindow,
            cpuAlertEnabled: cpuAlertEnabled,
            cpuAlertThreshold: cpuAlertThreshold,
            cpuAlertDuration: cpuAlertDuration,
            temperatureAlertEnabled: temperatureAlertEnabled,
            temperatureAlertThreshold: temperatureAlertThreshold,
            temperatureAlertDuration: temperatureAlertDuration
        )
    }
}

public struct AppSettingsV2: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var activeProfile: ProfileID
    public var customProfile: ProfileSettings
    public var autoSwitchRules: ProfileAutoSwitchRules
    public var privilegedTemperatureEnabled: Bool

    public init(
        schemaVersion: Int = 2,
        activeProfile: ProfileID,
        customProfile: ProfileSettings,
        autoSwitchRules: ProfileAutoSwitchRules,
        privilegedTemperatureEnabled: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.activeProfile = activeProfile
        self.customProfile = customProfile
        self.autoSwitchRules = autoSwitchRules
        self.privilegedTemperatureEnabled = privilegedTemperatureEnabled
    }

    public func settings(for profile: ProfileID) -> ProfileSettings {
        switch profile {
        case .quiet:
            return .quiet
        case .balanced:
            return .balanced
        case .performance:
            return .performance
        case .custom:
            return customProfile
        }
    }

    public static func migrated(from legacy: LegacySettingsSnapshot) -> AppSettingsV2 {
        AppSettingsV2(
            activeProfile: .custom,
            customProfile: legacy.asProfileSettings(),
            autoSwitchRules: .defaults,
            privilegedTemperatureEnabled: false
        )
    }
}
