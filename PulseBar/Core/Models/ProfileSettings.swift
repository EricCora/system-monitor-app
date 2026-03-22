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
    public var showCPUInMenu: Bool
    public var showMemoryInMenu: Bool
    public var showBatteryInMenu: Bool
    public var showNetworkInMenu: Bool
    public var showDiskInMenu: Bool
    public var showTemperatureInMenu: Bool
    public var throughputUnit: ThroughputDisplayUnit
    public var chartAreaOpacity: Double

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
        showCPUInMenu: Bool,
        showMemoryInMenu: Bool,
        showBatteryInMenu: Bool,
        showNetworkInMenu: Bool,
        showDiskInMenu: Bool,
        showTemperatureInMenu: Bool,
        throughputUnit: ThroughputDisplayUnit,
        chartAreaOpacity: Double,
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
        self.showCPUInMenu = showCPUInMenu
        self.showMemoryInMenu = showMemoryInMenu
        self.showBatteryInMenu = showBatteryInMenu
        self.showNetworkInMenu = showNetworkInMenu
        self.showDiskInMenu = showDiskInMenu
        self.showTemperatureInMenu = showTemperatureInMenu
        self.throughputUnit = throughputUnit
        self.chartAreaOpacity = chartAreaOpacity.clamped(to: 0.05...0.5)
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
        case showCPUInMenu
        case showMemoryInMenu
        case showBatteryInMenu
        case showNetworkInMenu
        case showDiskInMenu
        case showTemperatureInMenu
        case throughputUnit
        case chartAreaOpacity
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

        showCPUInMenu = try container.decode(Bool.self, forKey: .showCPUInMenu)
        showMemoryInMenu = try container.decode(Bool.self, forKey: .showMemoryInMenu)
        showBatteryInMenu = try container.decodeIfPresent(Bool.self, forKey: .showBatteryInMenu) ?? false
        showNetworkInMenu = try container.decode(Bool.self, forKey: .showNetworkInMenu)
        showDiskInMenu = try container.decode(Bool.self, forKey: .showDiskInMenu)
        showTemperatureInMenu = try container.decode(Bool.self, forKey: .showTemperatureInMenu)
        throughputUnit = try container.decode(ThroughputDisplayUnit.self, forKey: .throughputUnit)
        chartAreaOpacity = (try container.decodeIfPresent(Double.self, forKey: .chartAreaOpacity) ?? 0.18).clamped(to: 0.05...0.5)

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
        try container.encode(showCPUInMenu, forKey: .showCPUInMenu)
        try container.encode(showMemoryInMenu, forKey: .showMemoryInMenu)
        try container.encode(showBatteryInMenu, forKey: .showBatteryInMenu)
        try container.encode(showNetworkInMenu, forKey: .showNetworkInMenu)
        try container.encode(showDiskInMenu, forKey: .showDiskInMenu)
        try container.encode(showTemperatureInMenu, forKey: .showTemperatureInMenu)
        try container.encode(throughputUnit, forKey: .throughputUnit)
        try container.encode(chartAreaOpacity, forKey: .chartAreaOpacity)
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
        showCPUInMenu: true,
        showMemoryInMenu: true,
        showBatteryInMenu: false,
        showNetworkInMenu: false,
        showDiskInMenu: false,
        showTemperatureInMenu: true,
        throughputUnit: .bytesPerSecond,
        chartAreaOpacity: 0.18,
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
        showCPUInMenu: true,
        showMemoryInMenu: true,
        showBatteryInMenu: false,
        showNetworkInMenu: true,
        showDiskInMenu: false,
        showTemperatureInMenu: true,
        throughputUnit: .bytesPerSecond,
        chartAreaOpacity: 0.18,
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
        showCPUInMenu: true,
        showMemoryInMenu: true,
        showBatteryInMenu: true,
        showNetworkInMenu: true,
        showDiskInMenu: true,
        showTemperatureInMenu: true,
        throughputUnit: .bytesPerSecond,
        chartAreaOpacity: 0.18,
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
    public var chartAreaOpacity: Double
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
        chartAreaOpacity: Double,
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
        self.chartAreaOpacity = chartAreaOpacity.clamped(to: 0.05...0.5)
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
            showCPUInMenu: showCPUInMenu,
            showMemoryInMenu: showMemoryInMenu,
            showBatteryInMenu: showBatteryInMenu,
            showNetworkInMenu: showNetworkInMenu,
            showDiskInMenu: showDiskInMenu,
            showTemperatureInMenu: showTemperatureInMenu,
            throughputUnit: throughputUnit,
            chartAreaOpacity: chartAreaOpacity,
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

public struct AppSettingsV3: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var globalSamplingInterval: Double
    public var liveCompositorFPSEnabled: Bool
    public var activeProfile: ProfileID
    public var customProfile: ProfileSettings
    public var autoSwitchRules: ProfileAutoSwitchRules
    public var privilegedTemperatureEnabled: Bool
    public var cpuMenuLayout: MenuSectionLayout<CPUMenuSectionID>
    public var memoryMenuLayout: MenuSectionLayout<MemoryMenuSectionID>
    public var cpuProcessCount: Int
    public var memoryProcessCount: Int
    public var selectedCPUPaneChart: CPUPaneChart
    public var selectedMemoryPaneChart: MemoryPaneChart

    public init(
        schemaVersion: Int = 3,
        globalSamplingInterval: Double,
        liveCompositorFPSEnabled: Bool = false,
        activeProfile: ProfileID,
        customProfile: ProfileSettings,
        autoSwitchRules: ProfileAutoSwitchRules,
        privilegedTemperatureEnabled: Bool,
        cpuMenuLayout: MenuSectionLayout<CPUMenuSectionID> = .cpuDefault,
        memoryMenuLayout: MenuSectionLayout<MemoryMenuSectionID> = .memoryDefault,
        cpuProcessCount: Int = 5,
        memoryProcessCount: Int = 5,
        selectedCPUPaneChart: CPUPaneChart = .usage,
        selectedMemoryPaneChart: MemoryPaneChart = .composition
    ) {
        self.schemaVersion = schemaVersion
        self.globalSamplingInterval = globalSamplingInterval.clamped(to: 1...10)
        self.liveCompositorFPSEnabled = liveCompositorFPSEnabled
        self.activeProfile = activeProfile
        self.customProfile = customProfile
        self.autoSwitchRules = autoSwitchRules
        self.privilegedTemperatureEnabled = privilegedTemperatureEnabled
        self.cpuMenuLayout = cpuMenuLayout
        self.memoryMenuLayout = memoryMenuLayout
        self.cpuProcessCount = max(3, min(cpuProcessCount, 12))
        self.memoryProcessCount = max(3, min(memoryProcessCount, 12))
        self.selectedCPUPaneChart = selectedCPUPaneChart
        self.selectedMemoryPaneChart = selectedMemoryPaneChart
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

    public static func migrated(
        from v2: AppSettingsV2,
        legacySamplingInterval: Double?
    ) -> AppSettingsV3 {
        let fallbackInterval = samplingIntervalFallback(for: v2.activeProfile)
        return AppSettingsV3(
            globalSamplingInterval: (legacySamplingInterval ?? fallbackInterval).clamped(to: 1...10),
            liveCompositorFPSEnabled: false,
            activeProfile: v2.activeProfile,
            customProfile: v2.customProfile,
            autoSwitchRules: v2.autoSwitchRules,
            privilegedTemperatureEnabled: v2.privilegedTemperatureEnabled
        )
    }

    public static func migrated(from legacy: LegacySettingsSnapshot) -> AppSettingsV3 {
        AppSettingsV3(
            globalSamplingInterval: legacy.sampleInterval.clamped(to: 1...10),
            liveCompositorFPSEnabled: false,
            activeProfile: .custom,
            customProfile: legacy.asProfileSettings(),
            autoSwitchRules: .defaults,
            privilegedTemperatureEnabled: false
        )
    }

    private static func samplingIntervalFallback(for profile: ProfileID) -> Double {
        switch profile {
        case .quiet:
            return 5
        case .balanced:
            return 2
        case .performance:
            return 1
        case .custom:
            return 2
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case globalSamplingInterval
        case liveCompositorFPSEnabled
        case activeProfile
        case customProfile
        case autoSwitchRules
        case privilegedTemperatureEnabled
        case cpuMenuLayout
        case memoryMenuLayout
        case cpuProcessCount
        case memoryProcessCount
        case selectedCPUPaneChart
        case selectedMemoryPaneChart
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 3
        globalSamplingInterval = (try container.decode(Double.self, forKey: .globalSamplingInterval)).clamped(to: 1...10)
        liveCompositorFPSEnabled = try container.decodeIfPresent(Bool.self, forKey: .liveCompositorFPSEnabled) ?? false
        activeProfile = try container.decode(ProfileID.self, forKey: .activeProfile)
        customProfile = try container.decode(ProfileSettings.self, forKey: .customProfile)
        autoSwitchRules = try container.decode(ProfileAutoSwitchRules.self, forKey: .autoSwitchRules)
        privilegedTemperatureEnabled = try container.decode(Bool.self, forKey: .privilegedTemperatureEnabled)
        cpuMenuLayout = try container.decodeIfPresent(MenuSectionLayout<CPUMenuSectionID>.self, forKey: .cpuMenuLayout) ?? .cpuDefault
        memoryMenuLayout = try container.decodeIfPresent(MenuSectionLayout<MemoryMenuSectionID>.self, forKey: .memoryMenuLayout) ?? .memoryDefault
        cpuProcessCount = max(3, min((try container.decodeIfPresent(Int.self, forKey: .cpuProcessCount) ?? 5), 12))
        memoryProcessCount = max(3, min((try container.decodeIfPresent(Int.self, forKey: .memoryProcessCount) ?? 5), 12))
        selectedCPUPaneChart = try container.decodeIfPresent(CPUPaneChart.self, forKey: .selectedCPUPaneChart) ?? .usage
        selectedMemoryPaneChart = try container.decodeIfPresent(MemoryPaneChart.self, forKey: .selectedMemoryPaneChart) ?? .composition
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(globalSamplingInterval, forKey: .globalSamplingInterval)
        try container.encode(liveCompositorFPSEnabled, forKey: .liveCompositorFPSEnabled)
        try container.encode(activeProfile, forKey: .activeProfile)
        try container.encode(customProfile, forKey: .customProfile)
        try container.encode(autoSwitchRules, forKey: .autoSwitchRules)
        try container.encode(privilegedTemperatureEnabled, forKey: .privilegedTemperatureEnabled)
        try container.encode(cpuMenuLayout, forKey: .cpuMenuLayout)
        try container.encode(memoryMenuLayout, forKey: .memoryMenuLayout)
        try container.encode(cpuProcessCount, forKey: .cpuProcessCount)
        try container.encode(memoryProcessCount, forKey: .memoryProcessCount)
        try container.encode(selectedCPUPaneChart, forKey: .selectedCPUPaneChart)
        try container.encode(selectedMemoryPaneChart, forKey: .selectedMemoryPaneChart)
    }
}

public struct AppSettingsV4: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var globalSamplingInterval: Double
    public var liveCompositorFPSEnabled: Bool
    public var activeProfile: ProfileID
    public var customProfile: ProfileSettings
    public var autoSwitchRules: ProfileAutoSwitchRules
    public var privilegedTemperatureEnabled: Bool
    public var cpuMenuLayout: MenuSectionLayout<CPUMenuSectionID>
    public var memoryMenuLayout: MenuSectionLayout<MemoryMenuSectionID>
    public var cpuProcessCount: Int
    public var memoryProcessCount: Int
    public var selectedCPUPaneChart: CPUPaneChart
    public var selectedMemoryPaneChart: MemoryPaneChart
    public var dashboardLayout: DashboardLayoutMode
    public var dashboardCardOrder: [DashboardCardID]
    public var menuBarDisplayMode: MenuBarDisplayMode
    public var menuBarMetricStyles: [MenuBarMetricID: MenuBarMetricStyle]
    public var favoriteSensorIDs: [String]
    public var sensorPresets: [SensorPreset]
    public var selectedSensorPresetID: String?

    public init(
        schemaVersion: Int = 4,
        globalSamplingInterval: Double,
        liveCompositorFPSEnabled: Bool = false,
        activeProfile: ProfileID,
        customProfile: ProfileSettings,
        autoSwitchRules: ProfileAutoSwitchRules,
        privilegedTemperatureEnabled: Bool,
        cpuMenuLayout: MenuSectionLayout<CPUMenuSectionID> = .cpuDefault,
        memoryMenuLayout: MenuSectionLayout<MemoryMenuSectionID> = .memoryDefault,
        cpuProcessCount: Int = 5,
        memoryProcessCount: Int = 5,
        selectedCPUPaneChart: CPUPaneChart = .usage,
        selectedMemoryPaneChart: MemoryPaneChart = .composition,
        dashboardLayout: DashboardLayoutMode = .cardDashboard,
        dashboardCardOrder: [DashboardCardID] = DashboardCardID.defaultOrder,
        menuBarDisplayMode: MenuBarDisplayMode = .compact,
        menuBarMetricStyles: [MenuBarMetricID: MenuBarMetricStyle] = MenuBarMetricID.defaultStyles,
        favoriteSensorIDs: [String] = [],
        sensorPresets: [SensorPreset] = [],
        selectedSensorPresetID: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.globalSamplingInterval = globalSamplingInterval.clamped(to: 1...10)
        self.liveCompositorFPSEnabled = liveCompositorFPSEnabled
        self.activeProfile = activeProfile
        self.customProfile = customProfile
        self.autoSwitchRules = autoSwitchRules
        self.privilegedTemperatureEnabled = privilegedTemperatureEnabled
        self.cpuMenuLayout = cpuMenuLayout
        self.memoryMenuLayout = memoryMenuLayout
        self.cpuProcessCount = max(3, min(cpuProcessCount, 12))
        self.memoryProcessCount = max(3, min(memoryProcessCount, 12))
        self.selectedCPUPaneChart = selectedCPUPaneChart
        self.selectedMemoryPaneChart = selectedMemoryPaneChart
        self.dashboardLayout = dashboardLayout
        self.dashboardCardOrder = Self.normalizedCardOrder(dashboardCardOrder)
        self.menuBarDisplayMode = menuBarDisplayMode
        self.menuBarMetricStyles = Self.normalizedMetricStyles(menuBarMetricStyles)
        self.favoriteSensorIDs = Self.normalizedSensorIDs(favoriteSensorIDs)
        self.sensorPresets = Self.normalizedSensorPresets(sensorPresets)
        self.selectedSensorPresetID = selectedSensorPresetID
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

    public static func migrated(from v3: AppSettingsV3) -> AppSettingsV4 {
        AppSettingsV4(
            globalSamplingInterval: v3.globalSamplingInterval,
            liveCompositorFPSEnabled: v3.liveCompositorFPSEnabled,
            activeProfile: v3.activeProfile,
            customProfile: v3.customProfile,
            autoSwitchRules: v3.autoSwitchRules,
            privilegedTemperatureEnabled: v3.privilegedTemperatureEnabled,
            cpuMenuLayout: v3.cpuMenuLayout,
            memoryMenuLayout: v3.memoryMenuLayout,
            cpuProcessCount: v3.cpuProcessCount,
            memoryProcessCount: v3.memoryProcessCount,
            selectedCPUPaneChart: v3.selectedCPUPaneChart,
            selectedMemoryPaneChart: v3.selectedMemoryPaneChart
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case globalSamplingInterval
        case liveCompositorFPSEnabled
        case activeProfile
        case customProfile
        case autoSwitchRules
        case privilegedTemperatureEnabled
        case cpuMenuLayout
        case memoryMenuLayout
        case cpuProcessCount
        case memoryProcessCount
        case selectedCPUPaneChart
        case selectedMemoryPaneChart
        case dashboardLayout
        case dashboardCardOrder
        case menuBarDisplayMode
        case menuBarMetricStyles
        case favoriteSensorIDs
        case sensorPresets
        case selectedSensorPresetID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 4
        globalSamplingInterval = (try container.decode(Double.self, forKey: .globalSamplingInterval)).clamped(to: 1...10)
        liveCompositorFPSEnabled = try container.decodeIfPresent(Bool.self, forKey: .liveCompositorFPSEnabled) ?? false
        activeProfile = try container.decode(ProfileID.self, forKey: .activeProfile)
        customProfile = try container.decode(ProfileSettings.self, forKey: .customProfile)
        autoSwitchRules = try container.decode(ProfileAutoSwitchRules.self, forKey: .autoSwitchRules)
        privilegedTemperatureEnabled = try container.decode(Bool.self, forKey: .privilegedTemperatureEnabled)
        cpuMenuLayout = try container.decodeIfPresent(MenuSectionLayout<CPUMenuSectionID>.self, forKey: .cpuMenuLayout) ?? .cpuDefault
        memoryMenuLayout = try container.decodeIfPresent(MenuSectionLayout<MemoryMenuSectionID>.self, forKey: .memoryMenuLayout) ?? .memoryDefault
        cpuProcessCount = max(3, min((try container.decodeIfPresent(Int.self, forKey: .cpuProcessCount) ?? 5), 12))
        memoryProcessCount = max(3, min((try container.decodeIfPresent(Int.self, forKey: .memoryProcessCount) ?? 5), 12))
        selectedCPUPaneChart = try container.decodeIfPresent(CPUPaneChart.self, forKey: .selectedCPUPaneChart) ?? .usage
        selectedMemoryPaneChart = try container.decodeIfPresent(MemoryPaneChart.self, forKey: .selectedMemoryPaneChart) ?? .composition
        dashboardLayout = try container.decodeIfPresent(DashboardLayoutMode.self, forKey: .dashboardLayout) ?? .cardDashboard
        dashboardCardOrder = Self.normalizedCardOrder(
            try container.decodeIfPresent([DashboardCardID].self, forKey: .dashboardCardOrder) ?? DashboardCardID.defaultOrder
        )
        menuBarDisplayMode = try container.decodeIfPresent(MenuBarDisplayMode.self, forKey: .menuBarDisplayMode) ?? .compact
        menuBarMetricStyles = Self.normalizedMetricStyles(
            try container.decodeIfPresent([MenuBarMetricID: MenuBarMetricStyle].self, forKey: .menuBarMetricStyles) ?? MenuBarMetricID.defaultStyles
        )
        favoriteSensorIDs = Self.normalizedSensorIDs(
            try container.decodeIfPresent([String].self, forKey: .favoriteSensorIDs) ?? []
        )
        sensorPresets = Self.normalizedSensorPresets(
            try container.decodeIfPresent([SensorPreset].self, forKey: .sensorPresets) ?? []
        )
        selectedSensorPresetID = try container.decodeIfPresent(String.self, forKey: .selectedSensorPresetID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(globalSamplingInterval, forKey: .globalSamplingInterval)
        try container.encode(liveCompositorFPSEnabled, forKey: .liveCompositorFPSEnabled)
        try container.encode(activeProfile, forKey: .activeProfile)
        try container.encode(customProfile, forKey: .customProfile)
        try container.encode(autoSwitchRules, forKey: .autoSwitchRules)
        try container.encode(privilegedTemperatureEnabled, forKey: .privilegedTemperatureEnabled)
        try container.encode(cpuMenuLayout, forKey: .cpuMenuLayout)
        try container.encode(memoryMenuLayout, forKey: .memoryMenuLayout)
        try container.encode(cpuProcessCount, forKey: .cpuProcessCount)
        try container.encode(memoryProcessCount, forKey: .memoryProcessCount)
        try container.encode(selectedCPUPaneChart, forKey: .selectedCPUPaneChart)
        try container.encode(selectedMemoryPaneChart, forKey: .selectedMemoryPaneChart)
        try container.encode(dashboardLayout, forKey: .dashboardLayout)
        try container.encode(dashboardCardOrder, forKey: .dashboardCardOrder)
        try container.encode(menuBarDisplayMode, forKey: .menuBarDisplayMode)
        try container.encode(menuBarMetricStyles, forKey: .menuBarMetricStyles)
        try container.encode(favoriteSensorIDs, forKey: .favoriteSensorIDs)
        try container.encode(sensorPresets, forKey: .sensorPresets)
        try container.encodeIfPresent(selectedSensorPresetID, forKey: .selectedSensorPresetID)
    }

    private static func normalizedCardOrder(_ cards: [DashboardCardID]) -> [DashboardCardID] {
        var normalized: [DashboardCardID] = []
        for card in cards where !normalized.contains(card) {
            normalized.append(card)
        }
        for card in DashboardCardID.allCases where !normalized.contains(card) {
            normalized.append(card)
        }
        return normalized.isEmpty ? DashboardCardID.defaultOrder : normalized
    }

    private static func normalizedMetricStyles(
        _ styles: [MenuBarMetricID: MenuBarMetricStyle]
    ) -> [MenuBarMetricID: MenuBarMetricStyle] {
        var normalized = MenuBarMetricID.defaultStyles
        for metric in MenuBarMetricID.allCases {
            if let value = styles[metric] {
                normalized[metric] = value
            }
        }
        return normalized
    }

    private static func normalizedSensorIDs(_ sensorIDs: [String]) -> [String] {
        Array(NSOrderedSet(array: sensorIDs.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        })) as? [String] ?? []
    }

    private static func normalizedSensorPresets(_ presets: [SensorPreset]) -> [SensorPreset] {
        var seenIDs = Set<String>()
        return presets.compactMap { preset in
            guard !preset.name.isEmpty else { return nil }
            guard !seenIDs.contains(preset.id) else { return nil }
            seenIDs.insert(preset.id)
            return SensorPreset(id: preset.id, name: preset.name, sensorIDs: preset.sensorIDs)
        }
    }
}
