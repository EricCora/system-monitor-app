import Foundation
import PulseBarCore

@MainActor
final class SettingsController: ObservableObject {
    enum DefaultsKey {
        static let sampleInterval = "settings.sampleInterval"
        static let globalSamplingInterval = "settings.globalSamplingInterval"
        static let showCPUInMenu = "settings.showCPUInMenu"
        static let showMemoryInMenu = "settings.showMemoryInMenu"
        static let showBatteryInMenu = "settings.showBatteryInMenu"
        static let showNetworkInMenu = "settings.showNetworkInMenu"
        static let showDiskInMenu = "settings.showDiskInMenu"
        static let showTemperatureInMenu = "settings.showTemperatureInMenu"
        static let throughputUnit = "settings.throughputUnit"
        static let selectedWindow = "settings.selectedWindow"
        static let visibleChartWindows = "settings.visibleChartWindows"
        static let compactCPUChartWindow = "settings.compactCPUChartWindow"
        static let batteryChartWindow = "settings.batteryChartWindow"
        static let networkChartWindow = "settings.networkChartWindow"
        static let diskChartWindow = "settings.diskChartWindow"
        static let launchAtLogin = "settings.launchAtLogin"
        static let cpuAlertEnabled = "settings.cpuAlertEnabled"
        static let cpuAlertThreshold = "settings.cpuAlertThreshold"
        static let cpuAlertDuration = "settings.cpuAlertDuration"
        static let temperatureAlertEnabled = "settings.temperatureAlertEnabled"
        static let temperatureAlertThreshold = "settings.temperatureAlertThreshold"
        static let temperatureAlertDuration = "settings.temperatureAlertDuration"
        static let memoryPressureAlertEnabled = "settings.memoryPressureAlertEnabled"
        static let memoryPressureAlertThreshold = "settings.memoryPressureAlertThreshold"
        static let memoryPressureAlertDuration = "settings.memoryPressureAlertDuration"
        static let diskFreeAlertEnabled = "settings.diskFreeAlertEnabled"
        static let diskFreeAlertThresholdBytes = "settings.diskFreeAlertThresholdBytes"
        static let diskFreeAlertDuration = "settings.diskFreeAlertDuration"
        static let selectedProfileID = "settings.selectedProfileID"
        static let autoSwitchEnabled = "settings.autoSwitchEnabled"
        static let autoSwitchACProfile = "settings.autoSwitchACProfile"
        static let autoSwitchBatteryProfile = "settings.autoSwitchBatteryProfile"
        static let privilegedTemperatureEnabled = "settings.privilegedTemperatureEnabled"
        static let selectedMemoryHistoryWindow = "settings.selectedMemoryHistoryWindow"
        static let selectedCPUHistoryWindow = "settings.selectedCPUHistoryWindow"
        static let selectedTemperatureHistoryWindow = "settings.selectedTemperatureHistoryWindow"
        static let selectedMemoryPaneChart = "settings.selectedMemoryPaneChart"
        static let selectedCPUPaneChart = "settings.selectedCPUPaneChart"
        static let cpuProcessCount = "settings.cpuProcessCount"
        static let memoryProcessCount = "settings.memoryProcessCount"
        static let appSettingsV2 = "settings.v2.data"
        static let appSettingsV3 = "settings.v3.data"
        static let liveCompositorFPSEnabled = "settings.liveCompositorFPSEnabled"
    }

    private let defaults: UserDefaults
    private var bootstrapping = true
    private var isApplyingProfile = false
    private var customProfileSettings: ProfileSettings

    var onSamplingIntervalChanged: (@Sendable (Double) async -> Void)?
    var onLiveFPSChanged: (@Sendable (Bool) async -> Void)?
    var onPrivilegedTemperatureToggle: (@Sendable (Bool) async -> Void)?
    var onAlertSettingsChanged: (@Sendable () async -> Void)?
    var onLaunchAtLoginChanged: (@Sendable (Bool) async -> Void)?

    @Published var liveCompositorFPSEnabled: Bool {
        didSet {
            persist(liveCompositorFPSEnabled, key: DefaultsKey.liveCompositorFPSEnabled)
            Task { await onLiveFPSChanged?(liveCompositorFPSEnabled) }
            persistAppSettingsV3()
        }
    }

    @Published var selectedMemoryHistoryWindow: ChartWindow {
        didSet {
            persist(selectedMemoryHistoryWindow.rawValue, key: DefaultsKey.selectedMemoryHistoryWindow)
        }
    }

    @Published var selectedCPUHistoryWindow: ChartWindow {
        didSet {
            persist(selectedCPUHistoryWindow.rawValue, key: DefaultsKey.selectedCPUHistoryWindow)
            persistAppSettingsV3()
        }
    }

    @Published var selectedTemperatureHistoryWindow: ChartWindow {
        didSet {
            persist(selectedTemperatureHistoryWindow.rawValue, key: DefaultsKey.selectedTemperatureHistoryWindow)
        }
    }

    @Published var compactCPUChartWindow: ChartWindow {
        didSet {
            persist(compactCPUChartWindow.rawValue, key: DefaultsKey.compactCPUChartWindow)
        }
    }

    @Published var batteryChartWindow: ChartWindow {
        didSet {
            persist(batteryChartWindow.rawValue, key: DefaultsKey.batteryChartWindow)
        }
    }

    @Published var networkChartWindow: ChartWindow {
        didSet {
            persist(networkChartWindow.rawValue, key: DefaultsKey.networkChartWindow)
        }
    }

    @Published var diskChartWindow: ChartWindow {
        didSet {
            persist(diskChartWindow.rawValue, key: DefaultsKey.diskChartWindow)
        }
    }

    @Published var visibleChartWindows: [ChartWindow] {
        didSet {
            let normalized = Self.normalizeChartWindows(visibleChartWindows)
            if normalized != visibleChartWindows {
                visibleChartWindows = normalized
                return
            }
            persist(normalized.map(\.rawValue), key: DefaultsKey.visibleChartWindows)
        }
    }

    @Published var selectedMemoryPaneChart: MemoryPaneChart {
        didSet {
            persist(selectedMemoryPaneChart.rawValue, key: DefaultsKey.selectedMemoryPaneChart)
            persistAppSettingsV3()
        }
    }

    @Published var selectedCPUPaneChart: CPUPaneChart {
        didSet {
            persist(selectedCPUPaneChart.rawValue, key: DefaultsKey.selectedCPUPaneChart)
            persistAppSettingsV3()
        }
    }

    @Published var globalSamplingInterval: Double {
        didSet {
            let clamped = globalSamplingInterval.clamped(to: 1...10)
            if clamped != globalSamplingInterval {
                globalSamplingInterval = clamped
                return
            }
            persist(globalSamplingInterval, key: DefaultsKey.globalSamplingInterval)
            persist(globalSamplingInterval, key: DefaultsKey.sampleInterval)
            Task { await onSamplingIntervalChanged?(globalSamplingInterval) }
            persistAppSettingsV3()
        }
    }

    @Published var showCPUInMenu: Bool {
        didSet {
            persist(showCPUInMenu, key: DefaultsKey.showCPUInMenu)
            onProfileControlledSettingChanged()
        }
    }

    @Published var showMemoryInMenu: Bool {
        didSet {
            persist(showMemoryInMenu, key: DefaultsKey.showMemoryInMenu)
            onProfileControlledSettingChanged()
        }
    }

    @Published var showBatteryInMenu: Bool {
        didSet {
            persist(showBatteryInMenu, key: DefaultsKey.showBatteryInMenu)
            onProfileControlledSettingChanged()
        }
    }

    @Published var showNetworkInMenu: Bool {
        didSet {
            persist(showNetworkInMenu, key: DefaultsKey.showNetworkInMenu)
            onProfileControlledSettingChanged()
        }
    }

    @Published var showDiskInMenu: Bool {
        didSet {
            persist(showDiskInMenu, key: DefaultsKey.showDiskInMenu)
            onProfileControlledSettingChanged()
        }
    }

    @Published var showTemperatureInMenu: Bool {
        didSet {
            persist(showTemperatureInMenu, key: DefaultsKey.showTemperatureInMenu)
            onProfileControlledSettingChanged()
        }
    }

    @Published var throughputUnit: ThroughputDisplayUnit {
        didSet {
            persist(throughputUnit.rawValue, key: DefaultsKey.throughputUnit)
            onProfileControlledSettingChanged()
        }
    }

    @Published var chartAreaOpacity: Double {
        didSet {
            let clamped = chartAreaOpacity.clamped(to: 0.05...0.5)
            if clamped != chartAreaOpacity {
                chartAreaOpacity = clamped
                return
            }
            onProfileControlledSettingChanged()
        }
    }

    @Published var launchAtLoginEnabled: Bool {
        didSet {
            persist(launchAtLoginEnabled, key: DefaultsKey.launchAtLogin)
            Task { await onLaunchAtLoginChanged?(launchAtLoginEnabled) }
        }
    }

    @Published var privilegedTemperatureEnabled: Bool {
        didSet {
            persist(privilegedTemperatureEnabled, key: DefaultsKey.privilegedTemperatureEnabled)
            persistAppSettingsV3()
            Task { await onPrivilegedTemperatureToggle?(privilegedTemperatureEnabled) }
        }
    }

    @Published var selectedProfileID: ProfileID {
        didSet {
            persist(selectedProfileID.rawValue, key: DefaultsKey.selectedProfileID)
            guard selectedProfileID != oldValue else { return }
            guard !bootstrapping else { return }
            applyProfile(selectedProfileID)
        }
    }

    @Published var autoSwitchProfilesEnabled: Bool {
        didSet {
            persist(autoSwitchProfilesEnabled, key: DefaultsKey.autoSwitchEnabled)
            persistAppSettingsV3()
        }
    }

    @Published var autoSwitchACProfile: ProfileID {
        didSet {
            persist(autoSwitchACProfile.rawValue, key: DefaultsKey.autoSwitchACProfile)
            persistAppSettingsV3()
        }
    }

    @Published var autoSwitchBatteryProfile: ProfileID {
        didSet {
            persist(autoSwitchBatteryProfile.rawValue, key: DefaultsKey.autoSwitchBatteryProfile)
            persistAppSettingsV3()
        }
    }

    @Published var cpuAlertEnabled: Bool {
        didSet {
            persist(cpuAlertEnabled, key: DefaultsKey.cpuAlertEnabled)
            Task { await onAlertSettingsChanged?() }
            onProfileControlledSettingChanged()
        }
    }

    @Published var cpuAlertThreshold: Double {
        didSet {
            let clamped = min(max(cpuAlertThreshold, 1), 100)
            if clamped != cpuAlertThreshold {
                cpuAlertThreshold = clamped
                return
            }
            persist(cpuAlertThreshold, key: DefaultsKey.cpuAlertThreshold)
            Task { await onAlertSettingsChanged?() }
            onProfileControlledSettingChanged()
        }
    }

    @Published var cpuAlertDuration: Int {
        didSet {
            let clamped = max(cpuAlertDuration, 5)
            if clamped != cpuAlertDuration {
                cpuAlertDuration = clamped
                return
            }
            persist(cpuAlertDuration, key: DefaultsKey.cpuAlertDuration)
            Task { await onAlertSettingsChanged?() }
            onProfileControlledSettingChanged()
        }
    }

    @Published var temperatureAlertEnabled: Bool {
        didSet {
            persist(temperatureAlertEnabled, key: DefaultsKey.temperatureAlertEnabled)
            Task { await onAlertSettingsChanged?() }
            onProfileControlledSettingChanged()
        }
    }

    @Published var temperatureAlertThreshold: Double {
        didSet {
            let clamped = min(max(temperatureAlertThreshold, 40), 110)
            if clamped != temperatureAlertThreshold {
                temperatureAlertThreshold = clamped
                return
            }
            persist(temperatureAlertThreshold, key: DefaultsKey.temperatureAlertThreshold)
            Task { await onAlertSettingsChanged?() }
            onProfileControlledSettingChanged()
        }
    }

    @Published var temperatureAlertDuration: Int {
        didSet {
            let clamped = max(temperatureAlertDuration, 5)
            if clamped != temperatureAlertDuration {
                temperatureAlertDuration = clamped
                return
            }
            persist(temperatureAlertDuration, key: DefaultsKey.temperatureAlertDuration)
            Task { await onAlertSettingsChanged?() }
            onProfileControlledSettingChanged()
        }
    }

    @Published var memoryPressureAlertEnabled: Bool {
        didSet {
            persist(memoryPressureAlertEnabled, key: DefaultsKey.memoryPressureAlertEnabled)
            Task { await onAlertSettingsChanged?() }
            onProfileControlledSettingChanged()
        }
    }

    @Published var memoryPressureAlertThreshold: Double {
        didSet {
            let clamped = min(max(memoryPressureAlertThreshold, 1), 100)
            if clamped != memoryPressureAlertThreshold {
                memoryPressureAlertThreshold = clamped
                return
            }
            persist(memoryPressureAlertThreshold, key: DefaultsKey.memoryPressureAlertThreshold)
            Task { await onAlertSettingsChanged?() }
            onProfileControlledSettingChanged()
        }
    }

    @Published var memoryPressureAlertDuration: Int {
        didSet {
            let clamped = max(memoryPressureAlertDuration, 5)
            if clamped != memoryPressureAlertDuration {
                memoryPressureAlertDuration = clamped
                return
            }
            persist(memoryPressureAlertDuration, key: DefaultsKey.memoryPressureAlertDuration)
            Task { await onAlertSettingsChanged?() }
            onProfileControlledSettingChanged()
        }
    }

    @Published var diskFreeAlertEnabled: Bool {
        didSet {
            persist(diskFreeAlertEnabled, key: DefaultsKey.diskFreeAlertEnabled)
            Task { await onAlertSettingsChanged?() }
            onProfileControlledSettingChanged()
        }
    }

    @Published var diskFreeAlertThresholdBytes: Double {
        didSet {
            let clamped = min(max(diskFreeAlertThresholdBytes, 1 * 1_073_741_824), 2_000 * 1_073_741_824)
            if clamped != diskFreeAlertThresholdBytes {
                diskFreeAlertThresholdBytes = clamped
                return
            }
            persist(diskFreeAlertThresholdBytes, key: DefaultsKey.diskFreeAlertThresholdBytes)
            Task { await onAlertSettingsChanged?() }
            onProfileControlledSettingChanged()
        }
    }

    @Published var diskFreeAlertDuration: Int {
        didSet {
            let clamped = max(diskFreeAlertDuration, 5)
            if clamped != diskFreeAlertDuration {
                diskFreeAlertDuration = clamped
                return
            }
            persist(diskFreeAlertDuration, key: DefaultsKey.diskFreeAlertDuration)
            Task { await onAlertSettingsChanged?() }
            onProfileControlledSettingChanged()
        }
    }

    @Published var cpuMenuLayout: MenuSectionLayout<CPUMenuSectionID> {
        didSet {
            let normalized = cpuMenuLayout.reconciledEnsuringVisibleSections(fallback: .cpuDefault)
            if normalized != cpuMenuLayout {
                cpuMenuLayout = normalized
                return
            }
            persistAppSettingsV3()
        }
    }

    @Published var memoryMenuLayout: MenuSectionLayout<MemoryMenuSectionID> {
        didSet {
            let normalized = memoryMenuLayout.reconciledEnsuringVisibleSections(fallback: .memoryDefault)
            if normalized != memoryMenuLayout {
                memoryMenuLayout = normalized
                return
            }
            persistAppSettingsV3()
        }
    }

    @Published var cpuProcessCount: Int {
        didSet {
            let clamped = max(3, min(cpuProcessCount, 12))
            if clamped != cpuProcessCount {
                cpuProcessCount = clamped
                return
            }
            persist(cpuProcessCount, key: DefaultsKey.cpuProcessCount)
            persistAppSettingsV3()
        }
    }

    @Published var memoryProcessCount: Int {
        didSet {
            let clamped = max(3, min(memoryProcessCount, 12))
            if clamped != memoryProcessCount {
                memoryProcessCount = clamped
                return
            }
            persist(memoryProcessCount, key: DefaultsKey.memoryProcessCount)
            persistAppSettingsV3()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let legacy = Self.loadLegacySnapshot(defaults: defaults)
        let loadedV3 = Self.loadSettingsV3(defaults: defaults)
        let loadedV2 = Self.loadSettingsV2(defaults: defaults)
        let launchAtLogin = defaults.object(forKey: DefaultsKey.launchAtLogin) as? Bool ?? false
        let legacySelectedWindow = ChartWindow(
            legacyRawValue: defaults.string(forKey: DefaultsKey.selectedWindow) ?? ""
        )
        let selectedMemoryHistoryWindow = Self.loadChartWindow(
            defaults: defaults,
            key: DefaultsKey.selectedMemoryHistoryWindow,
            legacyFallback: legacySelectedWindow
        )
        let selectedCPUHistoryWindow = Self.loadChartWindow(
            defaults: defaults,
            key: DefaultsKey.selectedCPUHistoryWindow,
            legacyFallback: legacySelectedWindow
        )
        let selectedTemperatureHistoryWindow = Self.loadChartWindow(
            defaults: defaults,
            key: DefaultsKey.selectedTemperatureHistoryWindow,
            legacyFallback: legacySelectedWindow
        )
        let compactCPUChartWindow = Self.loadChartWindow(
            defaults: defaults,
            key: DefaultsKey.compactCPUChartWindow,
            legacyFallback: legacySelectedWindow
        )
        let batteryChartWindow = Self.loadChartWindow(
            defaults: defaults,
            key: DefaultsKey.batteryChartWindow,
            legacyFallback: legacySelectedWindow
        )
        let networkChartWindow = Self.loadChartWindow(
            defaults: defaults,
            key: DefaultsKey.networkChartWindow,
            legacyFallback: legacySelectedWindow
        )
        let diskChartWindow = Self.loadChartWindow(
            defaults: defaults,
            key: DefaultsKey.diskChartWindow,
            legacyFallback: legacySelectedWindow
        )
        let selectedMemoryPaneChart = MemoryPaneChart(
            rawValue: defaults.string(forKey: DefaultsKey.selectedMemoryPaneChart) ?? ""
        ) ?? .composition
        let selectedCPUPaneChart = CPUPaneChart(
            rawValue: defaults.string(forKey: DefaultsKey.selectedCPUPaneChart) ?? ""
        ) ?? .usage

        let appSettings: AppSettingsV3
        if let loadedV3 {
            appSettings = loadedV3
        } else if let loadedV2 {
            let legacySamplingInterval = defaults.object(forKey: DefaultsKey.globalSamplingInterval) as? Double
                ?? defaults.object(forKey: DefaultsKey.sampleInterval) as? Double
            appSettings = AppSettingsV3.migrated(from: loadedV2, legacySamplingInterval: legacySamplingInterval)
        } else {
            appSettings = AppSettingsV3.migrated(from: legacy)
        }

        let activeProfile = appSettings.activeProfile
        let customProfile = appSettings.customProfile
        let autoSwitchRules = appSettings.autoSwitchRules
        let profileSettings = appSettings.settings(for: activeProfile)

        customProfileSettings = customProfile
        globalSamplingInterval = appSettings.globalSamplingInterval.clamped(to: 1...10)
        liveCompositorFPSEnabled = appSettings.liveCompositorFPSEnabled
        showCPUInMenu = profileSettings.showCPUInMenu
        showMemoryInMenu = profileSettings.showMemoryInMenu
        showBatteryInMenu = profileSettings.showBatteryInMenu
        showNetworkInMenu = profileSettings.showNetworkInMenu
        showDiskInMenu = profileSettings.showDiskInMenu
        showTemperatureInMenu = profileSettings.showTemperatureInMenu
        throughputUnit = profileSettings.throughputUnit
        chartAreaOpacity = profileSettings.chartAreaOpacity
        launchAtLoginEnabled = launchAtLogin
        selectedProfileID = activeProfile
        autoSwitchProfilesEnabled = autoSwitchRules.isEnabled
        autoSwitchACProfile = autoSwitchRules.acProfile
        autoSwitchBatteryProfile = autoSwitchRules.batteryProfile
        privilegedTemperatureEnabled = appSettings.privilegedTemperatureEnabled
        cpuAlertEnabled = profileSettings.cpuAlertEnabled
        cpuAlertThreshold = profileSettings.cpuAlertThreshold
        cpuAlertDuration = profileSettings.cpuAlertDuration
        temperatureAlertEnabled = profileSettings.temperatureAlertEnabled
        temperatureAlertThreshold = profileSettings.temperatureAlertThreshold
        temperatureAlertDuration = profileSettings.temperatureAlertDuration
        memoryPressureAlertEnabled = profileSettings.memoryPressureAlertEnabled
        memoryPressureAlertThreshold = profileSettings.memoryPressureAlertThreshold
        memoryPressureAlertDuration = profileSettings.memoryPressureAlertDuration
        diskFreeAlertEnabled = profileSettings.diskFreeAlertEnabled
        diskFreeAlertThresholdBytes = profileSettings.diskFreeAlertThresholdBytes
        diskFreeAlertDuration = profileSettings.diskFreeAlertDuration
        self.selectedMemoryHistoryWindow = selectedMemoryHistoryWindow
        self.selectedCPUHistoryWindow = selectedCPUHistoryWindow
        self.selectedTemperatureHistoryWindow = selectedTemperatureHistoryWindow
        self.compactCPUChartWindow = compactCPUChartWindow
        self.batteryChartWindow = batteryChartWindow
        self.networkChartWindow = networkChartWindow
        self.diskChartWindow = diskChartWindow
        visibleChartWindows = Self.loadVisibleChartWindows(defaults: defaults)
        self.selectedMemoryPaneChart = selectedMemoryPaneChart
        self.selectedCPUPaneChart = selectedCPUPaneChart
        cpuMenuLayout = appSettings.cpuMenuLayout.reconciledEnsuringVisibleSections(fallback: .cpuDefault)
        memoryMenuLayout = appSettings.memoryMenuLayout.reconciledEnsuringVisibleSections(fallback: .memoryDefault)
        cpuProcessCount = appSettings.cpuProcessCount
        memoryProcessCount = appSettings.memoryProcessCount

        bootstrapping = false
        persistAppSettingsV3()
    }

    func currentAlertRules() -> [AlertRule] {
        [
            AlertRule(
                metricID: .cpuTotalPercent,
                threshold: cpuAlertThreshold,
                durationSeconds: cpuAlertDuration,
                isEnabled: cpuAlertEnabled,
                comparison: .aboveOrEqual
            ),
            AlertRule(
                metricID: .temperatureMaxCelsius,
                threshold: temperatureAlertThreshold,
                durationSeconds: temperatureAlertDuration,
                isEnabled: temperatureAlertEnabled,
                comparison: .aboveOrEqual
            ),
            AlertRule(
                metricID: .memoryPressureLevel,
                threshold: memoryPressureAlertThreshold,
                durationSeconds: memoryPressureAlertDuration,
                isEnabled: memoryPressureAlertEnabled,
                comparison: .aboveOrEqual
            ),
            AlertRule(
                metricID: .diskFreeBytes,
                threshold: diskFreeAlertThresholdBytes,
                durationSeconds: diskFreeAlertDuration,
                isEnabled: diskFreeAlertEnabled,
                comparison: .belowOrEqual
            )
        ]
    }

    func applyAutoSwitchProfile(_ profileID: ProfileID) {
        guard selectedProfileID != profileID else { return }
        selectedProfileID = profileID
    }

    private func applyProfile(_ profileID: ProfileID) {
        let settings = settings(for: profileID)
        isApplyingProfile = true
        showCPUInMenu = settings.showCPUInMenu
        showMemoryInMenu = settings.showMemoryInMenu
        showBatteryInMenu = settings.showBatteryInMenu
        showNetworkInMenu = settings.showNetworkInMenu
        showDiskInMenu = settings.showDiskInMenu
        showTemperatureInMenu = settings.showTemperatureInMenu
        throughputUnit = settings.throughputUnit
        chartAreaOpacity = settings.chartAreaOpacity
        cpuAlertEnabled = settings.cpuAlertEnabled
        cpuAlertThreshold = settings.cpuAlertThreshold
        cpuAlertDuration = settings.cpuAlertDuration
        temperatureAlertEnabled = settings.temperatureAlertEnabled
        temperatureAlertThreshold = settings.temperatureAlertThreshold
        temperatureAlertDuration = settings.temperatureAlertDuration
        memoryPressureAlertEnabled = settings.memoryPressureAlertEnabled
        memoryPressureAlertThreshold = settings.memoryPressureAlertThreshold
        memoryPressureAlertDuration = settings.memoryPressureAlertDuration
        diskFreeAlertEnabled = settings.diskFreeAlertEnabled
        diskFreeAlertThresholdBytes = settings.diskFreeAlertThresholdBytes
        diskFreeAlertDuration = settings.diskFreeAlertDuration
        isApplyingProfile = false
        persistAppSettingsV3()
    }

    private func settings(for profileID: ProfileID) -> ProfileSettings {
        switch profileID {
        case .quiet:
            return .quiet
        case .balanced:
            return .balanced
        case .performance:
            return .performance
        case .custom:
            return customProfileSettings
        }
    }

    private func currentProfileSettings() -> ProfileSettings {
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

    private func onProfileControlledSettingChanged() {
        guard !bootstrapping else { return }

        if isApplyingProfile {
            persistAppSettingsV3()
            return
        }

        customProfileSettings = currentProfileSettings()
        if selectedProfileID != .custom {
            selectedProfileID = .custom
            return
        }

        persistAppSettingsV3()
    }

    private func persistAppSettingsV3() {
        guard !bootstrapping else { return }

        let settings = AppSettingsV3(
            globalSamplingInterval: globalSamplingInterval,
            liveCompositorFPSEnabled: liveCompositorFPSEnabled,
            activeProfile: selectedProfileID,
            customProfile: customProfileSettings,
            autoSwitchRules: ProfileAutoSwitchRules(
                isEnabled: autoSwitchProfilesEnabled,
                acProfile: autoSwitchACProfile,
                batteryProfile: autoSwitchBatteryProfile
            ),
            privilegedTemperatureEnabled: privilegedTemperatureEnabled,
            cpuMenuLayout: cpuMenuLayout,
            memoryMenuLayout: memoryMenuLayout,
            cpuProcessCount: cpuProcessCount,
            memoryProcessCount: memoryProcessCount,
            selectedCPUPaneChart: selectedCPUPaneChart,
            selectedMemoryPaneChart: selectedMemoryPaneChart
        )

        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: DefaultsKey.appSettingsV3)
    }

    private func persist<T>(_ value: T, key: String) {
        guard !bootstrapping else { return }
        defaults.set(value, forKey: key)
    }

    private static func loadSettingsV3(defaults: UserDefaults) -> AppSettingsV3? {
        guard let data = defaults.data(forKey: DefaultsKey.appSettingsV3) else {
            return nil
        }
        return try? JSONDecoder().decode(AppSettingsV3.self, from: data)
    }

    private static func loadSettingsV2(defaults: UserDefaults) -> AppSettingsV2? {
        guard let data = defaults.data(forKey: DefaultsKey.appSettingsV2) else {
            return nil
        }
        return try? JSONDecoder().decode(AppSettingsV2.self, from: data)
    }

    private static func loadLegacySnapshot(defaults: UserDefaults) -> LegacySettingsSnapshot {
        let sampleInterval = defaults.object(forKey: DefaultsKey.globalSamplingInterval) as? Double
            ?? defaults.object(forKey: DefaultsKey.sampleInterval) as? Double
            ?? 2.0
        let showCPUInMenu = defaults.object(forKey: DefaultsKey.showCPUInMenu) as? Bool ?? true
        let showMemoryInMenu = defaults.object(forKey: DefaultsKey.showMemoryInMenu) as? Bool ?? true
        let showBatteryInMenu = defaults.object(forKey: DefaultsKey.showBatteryInMenu) as? Bool ?? false
        let showNetworkInMenu = defaults.object(forKey: DefaultsKey.showNetworkInMenu) as? Bool ?? true
        let showDiskInMenu = defaults.object(forKey: DefaultsKey.showDiskInMenu) as? Bool ?? false
        let showTemperatureInMenu = defaults.object(forKey: DefaultsKey.showTemperatureInMenu) as? Bool ?? true
        let throughputUnit = ThroughputDisplayUnit(rawValue: defaults.string(forKey: DefaultsKey.throughputUnit) ?? "")
            ?? .bytesPerSecond
        let selectedWindow = TimeWindow(rawValue: defaults.string(forKey: DefaultsKey.selectedWindow) ?? "") ?? .oneHour
        let cpuAlertEnabled = defaults.object(forKey: DefaultsKey.cpuAlertEnabled) as? Bool ?? false
        let cpuAlertThreshold = defaults.object(forKey: DefaultsKey.cpuAlertThreshold) as? Double ?? 85
        let cpuAlertDuration = defaults.object(forKey: DefaultsKey.cpuAlertDuration) as? Int ?? 30
        let temperatureAlertEnabled = defaults.object(forKey: DefaultsKey.temperatureAlertEnabled) as? Bool ?? false
        let temperatureAlertThreshold = defaults.object(forKey: DefaultsKey.temperatureAlertThreshold) as? Double ?? 92
        let temperatureAlertDuration = defaults.object(forKey: DefaultsKey.temperatureAlertDuration) as? Int ?? 20
        let memoryPressureAlertEnabled = defaults.object(forKey: DefaultsKey.memoryPressureAlertEnabled) as? Bool ?? false
        let memoryPressureAlertThreshold = defaults.object(forKey: DefaultsKey.memoryPressureAlertThreshold) as? Double ?? 90
        let memoryPressureAlertDuration = defaults.object(forKey: DefaultsKey.memoryPressureAlertDuration) as? Int ?? 30
        let diskFreeAlertEnabled = defaults.object(forKey: DefaultsKey.diskFreeAlertEnabled) as? Bool ?? false
        let diskFreeAlertThresholdBytes = defaults.object(forKey: DefaultsKey.diskFreeAlertThresholdBytes) as? Double
            ?? (20 * 1_073_741_824)
        let diskFreeAlertDuration = defaults.object(forKey: DefaultsKey.diskFreeAlertDuration) as? Int ?? 30

        return LegacySettingsSnapshot(
            sampleInterval: sampleInterval.clamped(to: 1...10),
            showCPUInMenu: showCPUInMenu,
            showMemoryInMenu: showMemoryInMenu,
            showBatteryInMenu: showBatteryInMenu,
            showNetworkInMenu: showNetworkInMenu,
            showDiskInMenu: showDiskInMenu,
            showTemperatureInMenu: showTemperatureInMenu,
            throughputUnit: throughputUnit,
            chartAreaOpacity: 0.18,
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

    var effectiveVisibleChartWindows: [ChartWindow] {
        Self.normalizeChartWindows(visibleChartWindows)
    }

    private static func normalizeChartWindows(_ windows: [ChartWindow]) -> [ChartWindow] {
        let normalized = ChartWindow.allCases.filter { windows.contains($0) }
        return normalized.isEmpty ? ChartWindow.allCases : normalized
    }

    private static func loadVisibleChartWindows(defaults: UserDefaults) -> [ChartWindow] {
        let rawValues = defaults.array(forKey: DefaultsKey.visibleChartWindows) as? [String] ?? []
        let parsed = rawValues.compactMap(ChartWindow.init(rawValue:))
        return normalizeChartWindows(parsed)
    }

    private static func loadChartWindow(
        defaults: UserDefaults,
        key: String,
        legacyFallback: ChartWindow
    ) -> ChartWindow {
        guard let rawValue = defaults.string(forKey: key), !rawValue.isEmpty else {
            return legacyFallback
        }
        return ChartWindow(rawValue: rawValue) ?? ChartWindow(legacyRawValue: rawValue)
    }
}
