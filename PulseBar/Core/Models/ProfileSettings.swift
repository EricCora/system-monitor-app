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
    public var showBatteryInMenu: Bool
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

    public var memoryPressureAlertEnabled: Bool
    public var memoryPressureAlertThreshold: Double
    public var memoryPressureAlertDuration: Int

    public var diskFreeAlertEnabled: Bool
    public var diskFreeAlertThresholdBytes: Double
    public var diskFreeAlertDuration: Int

    public init(
        sampleInterval: Double,
        showCPUInMenu: Bool,
        showMemoryInMenu: Bool,
        showBatteryInMenu: Bool,
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
        temperatureAlertDuration: Int,
        memoryPressureAlertEnabled: Bool,
        memoryPressureAlertThreshold: Double,
        memoryPressureAlertDuration: Int,
        diskFreeAlertEnabled: Bool,
        diskFreeAlertThresholdBytes: Double,
        diskFreeAlertDuration: Int
    ) {
        self.sampleInterval = sampleInterval
        self.showCPUInMenu = showCPUInMenu
        self.showMemoryInMenu = showMemoryInMenu
        self.showBatteryInMenu = showBatteryInMenu
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
        self.memoryPressureAlertEnabled = memoryPressureAlertEnabled
        self.memoryPressureAlertThreshold = memoryPressureAlertThreshold
        self.memoryPressureAlertDuration = memoryPressureAlertDuration
        self.diskFreeAlertEnabled = diskFreeAlertEnabled
        self.diskFreeAlertThresholdBytes = diskFreeAlertThresholdBytes
        self.diskFreeAlertDuration = diskFreeAlertDuration
    }

    private enum CodingKeys: String, CodingKey {
        case sampleInterval
        case showCPUInMenu
        case showMemoryInMenu
        case showBatteryInMenu
        case showNetworkInMenu
        case showDiskInMenu
        case showTemperatureInMenu
        case throughputUnit
        case selectedWindow
        case cpuAlertEnabled
        case cpuAlertThreshold
        case cpuAlertDuration
        case temperatureAlertEnabled
        case temperatureAlertThreshold
        case temperatureAlertDuration
        case memoryPressureAlertEnabled
        case memoryPressureAlertThreshold
        case memoryPressureAlertDuration
        case diskFreeAlertEnabled
        case diskFreeAlertThresholdBytes
        case diskFreeAlertDuration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        sampleInterval = try container.decode(Double.self, forKey: .sampleInterval)
        showCPUInMenu = try container.decode(Bool.self, forKey: .showCPUInMenu)
        showMemoryInMenu = try container.decode(Bool.self, forKey: .showMemoryInMenu)
        showBatteryInMenu = try container.decodeIfPresent(Bool.self, forKey: .showBatteryInMenu) ?? false
        showNetworkInMenu = try container.decode(Bool.self, forKey: .showNetworkInMenu)
        showDiskInMenu = try container.decode(Bool.self, forKey: .showDiskInMenu)
        showTemperatureInMenu = try container.decode(Bool.self, forKey: .showTemperatureInMenu)
        throughputUnit = try container.decode(ThroughputDisplayUnit.self, forKey: .throughputUnit)
        selectedWindow = try container.decode(TimeWindow.self, forKey: .selectedWindow)

        cpuAlertEnabled = try container.decode(Bool.self, forKey: .cpuAlertEnabled)
        cpuAlertThreshold = try container.decode(Double.self, forKey: .cpuAlertThreshold)
        cpuAlertDuration = try container.decode(Int.self, forKey: .cpuAlertDuration)
        temperatureAlertEnabled = try container.decode(Bool.self, forKey: .temperatureAlertEnabled)
        temperatureAlertThreshold = try container.decode(Double.self, forKey: .temperatureAlertThreshold)
        temperatureAlertDuration = try container.decode(Int.self, forKey: .temperatureAlertDuration)

        memoryPressureAlertEnabled = try container.decodeIfPresent(Bool.self, forKey: .memoryPressureAlertEnabled) ?? false
        memoryPressureAlertThreshold = try container.decodeIfPresent(Double.self, forKey: .memoryPressureAlertThreshold) ?? 90
        memoryPressureAlertDuration = try container.decodeIfPresent(Int.self, forKey: .memoryPressureAlertDuration) ?? 30
        diskFreeAlertEnabled = try container.decodeIfPresent(Bool.self, forKey: .diskFreeAlertEnabled) ?? false
        diskFreeAlertThresholdBytes = try container.decodeIfPresent(Double.self, forKey: .diskFreeAlertThresholdBytes) ?? (20 * 1_073_741_824)
        diskFreeAlertDuration = try container.decodeIfPresent(Int.self, forKey: .diskFreeAlertDuration) ?? 30
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sampleInterval, forKey: .sampleInterval)
        try container.encode(showCPUInMenu, forKey: .showCPUInMenu)
        try container.encode(showMemoryInMenu, forKey: .showMemoryInMenu)
        try container.encode(showBatteryInMenu, forKey: .showBatteryInMenu)
        try container.encode(showNetworkInMenu, forKey: .showNetworkInMenu)
        try container.encode(showDiskInMenu, forKey: .showDiskInMenu)
        try container.encode(showTemperatureInMenu, forKey: .showTemperatureInMenu)
        try container.encode(throughputUnit, forKey: .throughputUnit)
        try container.encode(selectedWindow, forKey: .selectedWindow)
        try container.encode(cpuAlertEnabled, forKey: .cpuAlertEnabled)
        try container.encode(cpuAlertThreshold, forKey: .cpuAlertThreshold)
        try container.encode(cpuAlertDuration, forKey: .cpuAlertDuration)
        try container.encode(temperatureAlertEnabled, forKey: .temperatureAlertEnabled)
        try container.encode(temperatureAlertThreshold, forKey: .temperatureAlertThreshold)
        try container.encode(temperatureAlertDuration, forKey: .temperatureAlertDuration)
        try container.encode(memoryPressureAlertEnabled, forKey: .memoryPressureAlertEnabled)
        try container.encode(memoryPressureAlertThreshold, forKey: .memoryPressureAlertThreshold)
        try container.encode(memoryPressureAlertDuration, forKey: .memoryPressureAlertDuration)
        try container.encode(diskFreeAlertEnabled, forKey: .diskFreeAlertEnabled)
        try container.encode(diskFreeAlertThresholdBytes, forKey: .diskFreeAlertThresholdBytes)
        try container.encode(diskFreeAlertDuration, forKey: .diskFreeAlertDuration)
    }

    public static let quiet = ProfileSettings(
        sampleInterval: 5,
        showCPUInMenu: true,
        showMemoryInMenu: true,
        showBatteryInMenu: false,
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
        temperatureAlertDuration: 30,
        memoryPressureAlertEnabled: false,
        memoryPressureAlertThreshold: 90,
        memoryPressureAlertDuration: 30,
        diskFreeAlertEnabled: false,
        diskFreeAlertThresholdBytes: 20 * 1_073_741_824,
        diskFreeAlertDuration: 30
    )

    public static let balanced = ProfileSettings(
        sampleInterval: 2,
        showCPUInMenu: true,
        showMemoryInMenu: true,
        showBatteryInMenu: false,
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
        temperatureAlertDuration: 20,
        memoryPressureAlertEnabled: false,
        memoryPressureAlertThreshold: 90,
        memoryPressureAlertDuration: 30,
        diskFreeAlertEnabled: false,
        diskFreeAlertThresholdBytes: 20 * 1_073_741_824,
        diskFreeAlertDuration: 30
    )

    public static let performance = ProfileSettings(
        sampleInterval: 1,
        showCPUInMenu: true,
        showMemoryInMenu: true,
        showBatteryInMenu: true,
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
        temperatureAlertDuration: 15,
        memoryPressureAlertEnabled: false,
        memoryPressureAlertThreshold: 92,
        memoryPressureAlertDuration: 20,
        diskFreeAlertEnabled: false,
        diskFreeAlertThresholdBytes: 25 * 1_073_741_824,
        diskFreeAlertDuration: 20
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
    public var showBatteryInMenu: Bool
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

    public var memoryPressureAlertEnabled: Bool
    public var memoryPressureAlertThreshold: Double
    public var memoryPressureAlertDuration: Int

    public var diskFreeAlertEnabled: Bool
    public var diskFreeAlertThresholdBytes: Double
    public var diskFreeAlertDuration: Int

    public init(
        sampleInterval: Double,
        showCPUInMenu: Bool,
        showMemoryInMenu: Bool,
        showBatteryInMenu: Bool,
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
        temperatureAlertDuration: Int,
        memoryPressureAlertEnabled: Bool,
        memoryPressureAlertThreshold: Double,
        memoryPressureAlertDuration: Int,
        diskFreeAlertEnabled: Bool,
        diskFreeAlertThresholdBytes: Double,
        diskFreeAlertDuration: Int
    ) {
        self.sampleInterval = sampleInterval
        self.showCPUInMenu = showCPUInMenu
        self.showMemoryInMenu = showMemoryInMenu
        self.showBatteryInMenu = showBatteryInMenu
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
        self.memoryPressureAlertEnabled = memoryPressureAlertEnabled
        self.memoryPressureAlertThreshold = memoryPressureAlertThreshold
        self.memoryPressureAlertDuration = memoryPressureAlertDuration
        self.diskFreeAlertEnabled = diskFreeAlertEnabled
        self.diskFreeAlertThresholdBytes = diskFreeAlertThresholdBytes
        self.diskFreeAlertDuration = diskFreeAlertDuration
    }

    public func asProfileSettings() -> ProfileSettings {
        ProfileSettings(
            sampleInterval: sampleInterval,
            showCPUInMenu: showCPUInMenu,
            showMemoryInMenu: showMemoryInMenu,
            showBatteryInMenu: showBatteryInMenu,
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
            temperatureAlertDuration: temperatureAlertDuration,
            memoryPressureAlertEnabled: memoryPressureAlertEnabled,
            memoryPressureAlertThreshold: memoryPressureAlertThreshold,
            memoryPressureAlertDuration: memoryPressureAlertDuration,
            diskFreeAlertEnabled: diskFreeAlertEnabled,
            diskFreeAlertThresholdBytes: diskFreeAlertThresholdBytes,
            diskFreeAlertDuration: diskFreeAlertDuration
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
