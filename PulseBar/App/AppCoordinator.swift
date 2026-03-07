import Foundation
import Combine
import PulseBarCore
import ServiceManagement
import UserNotifications

struct NetworkInterfaceRate: Identifiable {
    let interface: String
    let inboundBytesPerSecond: Double
    let outboundBytesPerSecond: Double

    var id: String { interface }
    var totalBytesPerSecond: Double { inboundBytesPerSecond + outboundBytesPerSecond }
}

@MainActor
final class AppCoordinator: ObservableObject {
    private enum DefaultsKey {
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
        static let selectedTemperatureSensorID = "settings.selectedTemperatureSensorID"
        static let selectedTemperatureHistoryWindow = "settings.selectedTemperatureHistoryWindow"
        static let selectedMemoryHistoryWindow = "settings.selectedMemoryHistoryWindow"
        static let selectedCPUHistoryWindow = "settings.selectedCPUHistoryWindow"
        static let selectedMemoryPaneChart = "settings.selectedMemoryPaneChart"
        static let selectedCPUPaneChart = "settings.selectedCPUPaneChart"
        static let hiddenTemperatureSensorIDs = "settings.hiddenTemperatureSensorIDs"
        static let cpuProcessCount = "settings.cpuProcessCount"
        static let memoryProcessCount = "settings.memoryProcessCount"
        static let appSettingsV2 = "settings.v2.data"
        static let appSettingsV3 = "settings.v3.data"
        static let liveCompositorFPSEnabled = "settings.liveCompositorFPSEnabled"
    }

    private let defaults: UserDefaults
    private let store: TimeSeriesStore
    private let alertEngine: AlertEngine
    private let samplingEngine: SamplingEngine
    private let isAppBundleRuntime: Bool
    private let temperatureCoordinator: TemperatureCoordinator
    private let temperatureHistoryStore: TemperatureHistoryStore
    private let memoryHistoryStore: MemoryHistoryStore
    private let metricHistoryStore: MetricHistoryStore
    private let processMemoryProvider: ProcessMemoryProvider
    private let processCPUProvider: ProcessCPUProvider
    private let gpuStatsProvider: GPUStatsProvider
    private let fpsProvider: FPSProvider
    private let alertDeliveryCenter: AlertDeliveryCenter
    private let powerSourceMonitor = PowerSourceMonitor()

    private var bootstrapping = true
    private var isApplyingProfile = false
    private var customProfileSettings: ProfileSettings

    @Published var latestSamples: [MetricID: MetricSample] = [:]
    @Published var launchAtLoginStatusMessage: String?
    @Published var privilegedTemperatureStatusMessage: String?
    @Published var privilegedTemperatureLastSuccessMessage: String?
    @Published var privilegedTemperatureHealthy: Bool = false
    @Published var latestTemperatureSensors: [TemperatureSensorReading] = []
    @Published var latestSensorChannels: [SensorReading] = []
    @Published var privilegedFanTelemetryHealthy: Bool = false
    @Published var privilegedChannelsAvailable: [SensorChannelType] = []
    @Published var privilegedActiveSourceChain: [String] = []
    @Published var privilegedSourceDiagnostics: [SensorSourceDiagnostic] = []
    @Published var fanParityGateBlocked: Bool = false
    @Published var fanParityGateMessage: String?
    @Published var temperatureHistoryStoreStatusMessage: String?
    @Published var memoryHistoryStoreStatusMessage: String?
    @Published var historyStoreStatusMessage: String?
    @Published var memoryProcessesStatusMessage: String?
    @Published var cpuProcessesStatusMessage: String?
    @Published var currentPowerSourceDescription: String = "Unknown"
    @Published var topMemoryProcesses: [MemoryProcessEntry] = []
    @Published var topCPUProcesses: [CPUProcessEntry] = []
    @Published var recentAlerts: [DeliveredAlert] = []
    @Published var latestGPUSummary: GPUSummarySnapshot?
    @Published var fpsStatusMessage: String?
    @Published var liveCompositorFPSEnabled: Bool {
        didSet {
            persist(liveCompositorFPSEnabled, key: DefaultsKey.liveCompositorFPSEnabled)
            Task {
                await fpsProvider.setLiveCaptureEnabled(liveCompositorFPSEnabled)
                fpsStatusMessage = await fpsProvider.currentStatusMessage()
            }
            persistAppSettingsV3()
        }
    }

    @Published var selectedTemperatureSensorID: String {
        didSet {
            persist(selectedTemperatureSensorID, key: DefaultsKey.selectedTemperatureSensorID)
        }
    }

    @Published var selectedTemperatureHistoryWindow: TemperatureHistoryWindow {
        didSet {
            persist(selectedTemperatureHistoryWindow.rawValue, key: DefaultsKey.selectedTemperatureHistoryWindow)
        }
    }

    @Published var selectedMemoryHistoryWindow: MemoryHistoryWindow {
        didSet {
            persist(selectedMemoryHistoryWindow.rawValue, key: DefaultsKey.selectedMemoryHistoryWindow)
        }
    }

    @Published var selectedCPUHistoryWindow: MetricHistoryWindow {
        didSet {
            persist(selectedCPUHistoryWindow.rawValue, key: DefaultsKey.selectedCPUHistoryWindow)
            persistAppSettingsV3()
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

    @Published var hiddenTemperatureSensorIDs: [String] {
        didSet {
            let normalized = Array(Set(hiddenTemperatureSensorIDs))
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            if normalized != hiddenTemperatureSensorIDs {
                hiddenTemperatureSensorIDs = normalized
                return
            }
            persist(hiddenTemperatureSensorIDs, key: DefaultsKey.hiddenTemperatureSensorIDs)
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
            Task {
                await samplingEngine.updateInterval(seconds: globalSamplingInterval)
                await processMemoryProvider.updateInterval(seconds: globalSamplingInterval)
                await processCPUProvider.updateInterval(seconds: globalSamplingInterval)
            }
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

    @Published var selectedWindow: TimeWindow {
        didSet {
            persist(selectedWindow.rawValue, key: DefaultsKey.selectedWindow)
            onProfileControlledSettingChanged()
        }
    }

    @Published var launchAtLoginEnabled: Bool {
        didSet {
            persist(launchAtLoginEnabled, key: DefaultsKey.launchAtLogin)
            Task { await updateLaunchAtLogin() }
        }
    }

    @Published var privilegedTemperatureEnabled: Bool {
        didSet {
            persist(privilegedTemperatureEnabled, key: DefaultsKey.privilegedTemperatureEnabled)
            persistAppSettingsV3()
            Task {
                await temperatureCoordinator.setPrivilegedEnabled(privilegedTemperatureEnabled)
                if privilegedTemperatureEnabled {
                    let samples = await temperatureCoordinator.probeNow()
                    await applyImmediatePrivilegedSamples(samples)
                }
                await refreshPrivilegedTemperatureStatus()
            }
        }
    }

    @Published var selectedProfileID: ProfileID {
        didSet {
            persist(selectedProfileID.rawValue, key: DefaultsKey.selectedProfileID)
            Task { await applySelectedProfileIfNeeded(previous: oldValue) }
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
            Task { await refreshAlertRules() }
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
            Task { await refreshAlertRules() }
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
            Task { await refreshAlertRules() }
            onProfileControlledSettingChanged()
        }
    }

    @Published var temperatureAlertEnabled: Bool {
        didSet {
            persist(temperatureAlertEnabled, key: DefaultsKey.temperatureAlertEnabled)
            Task { await refreshAlertRules() }
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
            Task { await refreshAlertRules() }
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
            Task { await refreshAlertRules() }
            onProfileControlledSettingChanged()
        }
    }

    @Published var memoryPressureAlertEnabled: Bool {
        didSet {
            persist(memoryPressureAlertEnabled, key: DefaultsKey.memoryPressureAlertEnabled)
            Task { await refreshAlertRules() }
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
            Task { await refreshAlertRules() }
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
            Task { await refreshAlertRules() }
            onProfileControlledSettingChanged()
        }
    }

    @Published var diskFreeAlertEnabled: Bool {
        didSet {
            persist(diskFreeAlertEnabled, key: DefaultsKey.diskFreeAlertEnabled)
            Task { await refreshAlertRules() }
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
            Task { await refreshAlertRules() }
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
            Task { await refreshAlertRules() }
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
        self.isAppBundleRuntime = Bundle.main.bundleURL.pathExtension == "app"
        let alertDeliveryCenter = AlertDeliveryCenter(isAppBundleRuntime: Bundle.main.bundleURL.pathExtension == "app")
        self.alertDeliveryCenter = alertDeliveryCenter

        let legacy = AppCoordinator.loadLegacySnapshot(defaults: defaults)
        let loadedV3 = AppCoordinator.loadSettingsV3(defaults: defaults)
        let loadedV2 = AppCoordinator.loadSettingsV2(defaults: defaults)
        let launchAtLogin = defaults.object(forKey: DefaultsKey.launchAtLogin) as? Bool ?? false
        let selectedTemperatureSensorID = defaults.string(forKey: DefaultsKey.selectedTemperatureSensorID) ?? ""
        let selectedTemperatureHistoryWindow = TemperatureHistoryWindow(
            rawValue: defaults.string(forKey: DefaultsKey.selectedTemperatureHistoryWindow) ?? ""
        ) ?? .oneHour
        let selectedMemoryHistoryWindow = MemoryHistoryWindow(
            rawValue: defaults.string(forKey: DefaultsKey.selectedMemoryHistoryWindow) ?? ""
        ) ?? .oneHour
        let selectedCPUHistoryWindow = MetricHistoryWindow(
            rawValue: defaults.string(forKey: DefaultsKey.selectedCPUHistoryWindow) ?? ""
        ) ?? .oneHour
        let selectedMemoryPaneChart = MemoryPaneChart(
            rawValue: defaults.string(forKey: DefaultsKey.selectedMemoryPaneChart) ?? ""
        ) ?? .composition
        let selectedCPUPaneChart = CPUPaneChart(
            rawValue: defaults.string(forKey: DefaultsKey.selectedCPUPaneChart) ?? ""
        ) ?? .usage
        let hiddenTemperatureSensorIDs = (defaults.array(forKey: DefaultsKey.hiddenTemperatureSensorIDs) as? [String] ?? [])
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let appSettings: AppSettingsV3
        let activeProfile: ProfileID
        let customProfile: ProfileSettings
        let autoSwitchRules: ProfileAutoSwitchRules
        let privilegedTemperatureEnabled: Bool
        let profileSettings: ProfileSettings
        let globalSamplingInterval: Double
        let liveCompositorFPSEnabled: Bool

        if let loadedV3 {
            appSettings = loadedV3
        } else if let loadedV2 {
            let legacySamplingInterval = defaults.object(forKey: DefaultsKey.globalSamplingInterval) as? Double
                ?? defaults.object(forKey: DefaultsKey.sampleInterval) as? Double
            appSettings = AppSettingsV3.migrated(from: loadedV2, legacySamplingInterval: legacySamplingInterval)
        } else {
            appSettings = AppSettingsV3.migrated(from: legacy)
        }

        activeProfile = appSettings.activeProfile
        customProfile = appSettings.customProfile
        autoSwitchRules = appSettings.autoSwitchRules
        privilegedTemperatureEnabled = appSettings.privilegedTemperatureEnabled
        profileSettings = appSettings.settings(for: appSettings.activeProfile)
        globalSamplingInterval = appSettings.globalSamplingInterval
        liveCompositorFPSEnabled = appSettings.liveCompositorFPSEnabled

        self.customProfileSettings = customProfile

        self.globalSamplingInterval = globalSamplingInterval.clamped(to: 1...10)
        self.liveCompositorFPSEnabled = liveCompositorFPSEnabled
        self.showCPUInMenu = profileSettings.showCPUInMenu
        self.showMemoryInMenu = profileSettings.showMemoryInMenu
        self.showBatteryInMenu = profileSettings.showBatteryInMenu
        self.showNetworkInMenu = profileSettings.showNetworkInMenu
        self.showDiskInMenu = profileSettings.showDiskInMenu
        self.showTemperatureInMenu = profileSettings.showTemperatureInMenu
        self.throughputUnit = profileSettings.throughputUnit
        self.selectedWindow = profileSettings.selectedWindow
        self.launchAtLoginEnabled = launchAtLogin
        self.selectedProfileID = activeProfile
        self.autoSwitchProfilesEnabled = autoSwitchRules.isEnabled
        self.autoSwitchACProfile = autoSwitchRules.acProfile
        self.autoSwitchBatteryProfile = autoSwitchRules.batteryProfile
        self.privilegedTemperatureEnabled = privilegedTemperatureEnabled
        self.cpuAlertEnabled = profileSettings.cpuAlertEnabled
        self.cpuAlertThreshold = profileSettings.cpuAlertThreshold
        self.cpuAlertDuration = profileSettings.cpuAlertDuration
        self.temperatureAlertEnabled = profileSettings.temperatureAlertEnabled
        self.temperatureAlertThreshold = profileSettings.temperatureAlertThreshold
        self.temperatureAlertDuration = profileSettings.temperatureAlertDuration
        self.memoryPressureAlertEnabled = profileSettings.memoryPressureAlertEnabled
        self.memoryPressureAlertThreshold = profileSettings.memoryPressureAlertThreshold
        self.memoryPressureAlertDuration = profileSettings.memoryPressureAlertDuration
        self.diskFreeAlertEnabled = profileSettings.diskFreeAlertEnabled
        self.diskFreeAlertThresholdBytes = profileSettings.diskFreeAlertThresholdBytes
        self.diskFreeAlertDuration = profileSettings.diskFreeAlertDuration
        self.selectedTemperatureSensorID = selectedTemperatureSensorID
        self.selectedTemperatureHistoryWindow = selectedTemperatureHistoryWindow
        self.selectedMemoryHistoryWindow = selectedMemoryHistoryWindow
        self.selectedCPUHistoryWindow = selectedCPUHistoryWindow
        self.selectedMemoryPaneChart = selectedMemoryPaneChart
        self.selectedCPUPaneChart = selectedCPUPaneChart
        self.hiddenTemperatureSensorIDs = hiddenTemperatureSensorIDs
        self.cpuMenuLayout = appSettings.cpuMenuLayout.reconciledEnsuringVisibleSections(fallback: .cpuDefault)
        self.memoryMenuLayout = appSettings.memoryMenuLayout.reconciledEnsuringVisibleSections(fallback: .memoryDefault)
        self.cpuProcessCount = appSettings.cpuProcessCount
        self.memoryProcessCount = appSettings.memoryProcessCount

        self.store = TimeSeriesStore(defaultCapacity: 7200)
        self.temperatureHistoryStore = TemperatureHistoryStore()
        self.memoryHistoryStore = MemoryHistoryStore()
        self.metricHistoryStore = MetricHistoryStore()
        self.processMemoryProvider = ProcessMemoryProvider(maxEntries: 12, minCollectionInterval: globalSamplingInterval)
        self.processCPUProvider = ProcessCPUProvider(maxEntries: 12, minCollectionInterval: globalSamplingInterval)
        let gpuStatsProvider = GPUStatsProvider()
        self.gpuStatsProvider = gpuStatsProvider

        self.alertEngine = AlertEngine { title, body in
            _ = await alertDeliveryCenter.deliver(title: title, body: body)
        }

        let privilegedSource = PrivilegedHelperTemperatureDataSource()
        let powermetricsProvider = PowermetricsProvider(
            dataSource: privilegedSource,
            minCollectionInterval: globalSamplingInterval
        )
        self.temperatureCoordinator = TemperatureCoordinator(provider: powermetricsProvider)
        let fpsProvider = FPSProvider(liveCaptureEnabled: liveCompositorFPSEnabled)
        self.fpsProvider = fpsProvider

        let providers: [any MetricProvider] = [
            CPUProvider(),
            ThermalStateProvider(),
            BatteryProvider(),
            MemoryProvider(),
            NetworkProvider(),
            DiskProvider(),
            gpuStatsProvider,
            fpsProvider,
            powermetricsProvider
        ]

        self.samplingEngine = SamplingEngine(
            providers: providers,
            store: store,
            intervalSeconds: globalSamplingInterval.clamped(to: 1...10)
        )

        bootstrapping = false
        persistAppSettingsV3()

        Task {
            await samplingEngine.setOnBatch { [weak self] batch in
                await self?.handle(batch: batch)
            }
            if let historyStartupError = await temperatureHistoryStore.startupError() {
                temperatureHistoryStoreStatusMessage = "Temperature history database unavailable: \(historyStartupError)"
            } else {
                temperatureHistoryStoreStatusMessage = nil
            }
            if let memoryHistoryStartupError = await memoryHistoryStore.startupError() {
                memoryHistoryStoreStatusMessage = "Memory history database unavailable: \(memoryHistoryStartupError)"
            } else {
                memoryHistoryStoreStatusMessage = nil
            }
            if let metricHistoryStartupError = await metricHistoryStore.startupError() {
                historyStoreStatusMessage = "Metric history database unavailable: \(metricHistoryStartupError)"
            } else {
                historyStoreStatusMessage = nil
            }
            await hydrateLatestSamplesFromPersistentHistory()
            recentAlerts = alertDeliveryCenter.recentAlerts
            await alertDeliveryCenter.requestAuthorizationIfNeeded()
            await temperatureCoordinator.setPrivilegedEnabled(privilegedTemperatureEnabled)
            await refreshAlertRules()
            await updateLaunchAtLogin()
            await refreshMemoryProcesses(at: Date())
            await refreshCPUProcesses(at: Date())
            latestGPUSummary = await gpuStatsProvider.currentSnapshot()
            fpsStatusMessage = await fpsProvider.currentStatusMessage()
            await refreshPrivilegedTemperatureStatus()
            await powerSourceMonitor.start { [weak self] source in
                await self?.handlePowerSourceChange(source)
            }
            await samplingEngine.start()
        }
    }

    func series(for metricID: MetricID, window: TimeWindow? = nil, maxPoints: Int = 300) async -> [MetricSample] {
        let selected = window ?? selectedWindow
        if historyStoreStatusMessage == nil {
            return await metricHistoryStore.series(for: metricID, window: selected, maxPoints: maxPoints)
        }
        let raw = await store.series(for: metricID, window: selected)
        return Downsampler.downsample(raw, maxPoints: maxPoints)
    }

    func metricHistorySeries(
        for metricID: MetricID,
        window: MetricHistoryWindow,
        maxPoints: Int = 900
    ) async -> [MetricHistoryPoint] {
        await metricHistoryStore.series(for: metricID, window: window, maxPoints: maxPoints)
    }

    func temperatureHistorySeries(
        sensorID: String,
        channelType: SensorChannelType,
        window: TemperatureHistoryWindow,
        maxPoints: Int = 900
    ) async -> [TemperatureHistoryPoint] {
        await temperatureHistoryStore.series(
            sensorID: sensorID,
            channelType: channelType,
            window: window,
            maxPoints: maxPoints
        )
    }

    func memoryHistorySeries(
        window: MemoryHistoryWindow,
        maxPoints: Int = 900
    ) async -> [MemoryHistoryPoint] {
        await memoryHistoryStore.series(
            window: window,
            maxPoints: maxPoints
        )
    }

    func visibleSensorChannels() -> [SensorReading] {
        latestSensorChannels.filter { !hiddenTemperatureSensorIDs.contains($0.id) }
    }

    func selectedSensorReading(includeHidden: Bool = false) -> SensorReading? {
        let source = includeHidden ? latestSensorChannels : visibleSensorChannels()
        return source.first { $0.id == selectedTemperatureSensorID }
    }

    func hideTemperatureSensor(sensorID: String) {
        guard !sensorID.isEmpty else { return }
        guard !hiddenTemperatureSensorIDs.contains(sensorID) else { return }
        hiddenTemperatureSensorIDs.append(sensorID)

        if selectedTemperatureSensorID == sensorID {
            selectedTemperatureSensorID = visibleSensorChannels().first?.id ?? ""
        }
    }

    func resetHiddenTemperatureSensors() {
        hiddenTemperatureSensorIDs = []
        if selectedTemperatureSensorID.isEmpty {
            selectedTemperatureSensorID = visibleSensorChannels().first?.id ?? ""
        }
    }

    func isTemperatureSensorHidden(sensorID: String) -> Bool {
        hiddenTemperatureSensorIDs.contains(sensorID)
    }

    func latestValue(for metricID: MetricID) -> MetricSample? {
        latestSamples[metricID]
    }

    func hasBatteryTelemetry() -> Bool {
        latestSamples[.batteryChargePercent] != nil || latestSamples[.batteryIsCharging] != nil
    }

    func latestCPUCores() -> [MetricSample] {
        latestSamples
            .values
            .filter {
                if case .cpuCorePercent = $0.metricID {
                    return true
                }
                return false
            }
            .sorted { lhs, rhs in
                guard case .cpuCorePercent(let l) = lhs.metricID,
                      case .cpuCorePercent(let r) = rhs.metricID else {
                    return false
                }
                return l < r
            }
    }

    func latestNetworkInterfaces() -> [NetworkInterfaceRate] {
        var inboundByInterface: [String: Double] = [:]
        var outboundByInterface: [String: Double] = [:]

        for sample in latestSamples.values {
            switch sample.metricID {
            case .networkInterfaceInBytesPerSec(let interface):
                inboundByInterface[interface] = sample.value
            case .networkInterfaceOutBytesPerSec(let interface):
                outboundByInterface[interface] = sample.value
            default:
                continue
            }
        }

        let allInterfaces = Set(inboundByInterface.keys).union(outboundByInterface.keys)
        return allInterfaces
            .map { interface in
                NetworkInterfaceRate(
                    interface: interface,
                    inboundBytesPerSecond: inboundByInterface[interface] ?? 0,
                    outboundBytesPerSecond: outboundByInterface[interface] ?? 0
                )
            }
            .sorted { lhs, rhs in
                if lhs.totalBytesPerSecond != rhs.totalBytesPerSecond {
                    return lhs.totalBytesPerSecond > rhs.totalBytesPerSecond
                }
                return lhs.interface.localizedCaseInsensitiveCompare(rhs.interface) == .orderedAscending
            }
    }

    func latestThermalState() -> ThermalStateLevel {
        let value = latestSamples[.thermalStateLevel]?.value ?? ThermalStateLevel.nominal.metricValue
        return ThermalStateLevel.from(metricValue: value)
    }

    func cpuSummarySnapshot() -> CPUSummarySnapshot {
        CPUSummarySnapshot(
            userPercent: latestSamples[.cpuUserPercent]?.value ?? 0,
            systemPercent: latestSamples[.cpuSystemPercent]?.value ?? 0,
            idlePercent: latestSamples[.cpuIdlePercent]?.value ?? 100,
            loadAverages: CPUSummarySnapshot.LoadAverageSnapshot(
                one: latestSamples[.cpuLoadAverage1]?.value ?? 0,
                five: latestSamples[.cpuLoadAverage5]?.value ?? 0,
                fifteen: latestSamples[.cpuLoadAverage15]?.value ?? 0
            ),
            framesPerSecond: latestSamples[.framesPerSecond]?.value,
            uptimeSeconds: latestSamples[.uptimeSeconds]?.value ?? ProcessInfo.processInfo.systemUptime,
            gpu: latestGPUSummary
        )
    }

    func retryPrivilegedTemperatureNow() {
        Task {
            await temperatureCoordinator.requestImmediateRetry()
            let samples = await temperatureCoordinator.probeNow()
            await applyImmediatePrivilegedSamples(samples)
            await refreshPrivilegedTemperatureStatus()
        }
    }

    private func handle(batch: [MetricSample]) async {
        await alertEngine.process(samples: batch)
        let tickTimestamp = batch.first?.timestamp ?? Date()
        await metricHistoryStore.append(samples: batch, now: tickTimestamp)

        await MainActor.run {
            let incomingMetricIDs = Set(batch.map(\.metricID))

            let includesNetworkAggregate = incomingMetricIDs.contains(.networkInBytesPerSec)
                || incomingMetricIDs.contains(.networkOutBytesPerSec)
            if includesNetworkAggregate {
                for metricID in latestSamples.keys {
                    switch metricID {
                    case .networkInterfaceInBytesPerSec, .networkInterfaceOutBytesPerSec:
                        if !incomingMetricIDs.contains(metricID) {
                            latestSamples[metricID] = nil
                        }
                    default:
                        break
                    }
                }
            }

            let includesDiskAggregate = incomingMetricIDs.contains(.diskThroughputBytesPerSec)
            let includesDiskSplit = incomingMetricIDs.contains(.diskReadBytesPerSec)
                || incomingMetricIDs.contains(.diskWriteBytesPerSec)
            if includesDiskAggregate && !includesDiskSplit {
                latestSamples[.diskReadBytesPerSec] = nil
                latestSamples[.diskWriteBytesPerSec] = nil
            }

            for sample in batch {
                latestSamples[sample.metricID] = sample
            }

            recentAlerts = alertDeliveryCenter.recentAlerts
        }

        await appendMemoryHistoryPointIfAvailable(at: tickTimestamp)
        await refreshMemoryProcesses(at: tickTimestamp)
        await refreshCPUProcesses(at: tickTimestamp)
        latestGPUSummary = await gpuStatsProvider.currentSnapshot()
        fpsStatusMessage = await fpsProvider.currentStatusMessage()
        await refreshPrivilegedTemperatureStatus()
    }

    private func applyImmediatePrivilegedSamples(_ samples: [MetricSample]) async {
        guard !samples.isEmpty else { return }
        await handle(batch: samples)
    }

    private func appendMemoryHistoryPointIfAvailable(at timestamp: Date) async {
        guard let appBytes = latestSamples[.memoryAppBytes]?.value,
              let wiredBytes = latestSamples[.memoryWiredBytes]?.value,
              let activeBytes = latestSamples[.memoryActiveBytes]?.value,
              let compressedBytes = latestSamples[.memoryCompressedBytes]?.value,
              let cacheBytes = latestSamples[.memoryCacheBytes]?.value,
              let freeBytes = latestSamples[.memoryFreeBytes]?.value,
              let pressurePercent = latestSamples[.memoryPressureLevel]?.value else {
            return
        }

        let reportedTotal = latestSamples[.memoryUsedBytes].map { $0.value + freeBytes } ?? 0
        let totalBytes = max(reportedTotal, Double(ProcessInfo.processInfo.physicalMemory))

        await memoryHistoryStore.append(
            point: MemoryHistoryPoint(
                timestamp: timestamp,
                appBytes: appBytes,
                wiredBytes: wiredBytes,
                activeBytes: activeBytes,
                compressedBytes: compressedBytes,
                cacheBytes: cacheBytes,
                freeBytes: freeBytes,
                totalBytes: totalBytes,
                pressurePercent: pressurePercent
            )
        )
    }

    private func refreshMemoryProcesses(at date: Date) async {
        let entries = await processMemoryProvider.topProcesses(at: date)
        let status = await processMemoryProvider.statusMessage()
        topMemoryProcesses = Array(entries.prefix(memoryProcessCount))
        if let status {
            memoryProcessesStatusMessage = "Process memory list unavailable: \(status)"
        } else {
            memoryProcessesStatusMessage = nil
        }
    }

    private func refreshCPUProcesses(at date: Date) async {
        let entries = await processCPUProvider.topProcesses(at: date)
        let status = await processCPUProvider.statusMessage()
        topCPUProcesses = Array(entries.prefix(cpuProcessCount))
        if let status {
            cpuProcessesStatusMessage = "CPU process list unavailable: \(status)"
        } else {
            cpuProcessesStatusMessage = nil
        }
    }

    private func refreshAlertRules() async {
        let rules = [
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
        await alertEngine.updateRules(rules)
    }

    private func applySelectedProfileIfNeeded(previous: ProfileID) async {
        guard selectedProfileID != previous else { return }
        guard !bootstrapping else { return }
        applyProfile(selectedProfileID)
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
        selectedWindow = settings.selectedWindow
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

    private func refreshPrivilegedTemperatureStatus() async {
        let status = await temperatureCoordinator.currentStatus()

        if !status.isEnabled {
            privilegedTemperatureStatusMessage = "Privileged mode off (standard thermal state only)."
            privilegedTemperatureLastSuccessMessage = nil
            privilegedTemperatureHealthy = false
            latestTemperatureSensors = []
            latestSensorChannels = []
            privilegedFanTelemetryHealthy = false
            privilegedChannelsAvailable = []
            privilegedActiveSourceChain = []
            privilegedSourceDiagnostics = []
            fanParityGateBlocked = false
            fanParityGateMessage = nil
            return
        }

        if let error = status.lastErrorMessage {
            if error.localizedCaseInsensitiveContains("cancelled")
                || error.localizedCaseInsensitiveContains("canceled") {
                privilegedTemperatureStatusMessage = "Privileged mode blocked: administrator authorization was cancelled. PulseBar is using standard thermal state."
            } else if error.localizedCaseInsensitiveContains("launch failed") {
                privilegedTemperatureStatusMessage = "Privileged mode blocked: helper launch failed. Retry and confirm administrator approval."
            } else if error.localizedCaseInsensitiveContains("binary not found") {
                privilegedTemperatureStatusMessage = "Privileged mode blocked: helper binary not found. Build PulseBarPrivilegedHelper and retry."
            } else if error.localizedCaseInsensitiveContains("not available yet") {
                privilegedTemperatureStatusMessage = "Privileged mode is starting. Waiting for helper readiness."
            } else if error.localizedCaseInsensitiveContains("empty response") {
                privilegedTemperatureStatusMessage = "Privileged mode degraded: helper started but no data was returned. Retrying automatically."
            } else if error.localizedCaseInsensitiveContains("did not expose celsius temperature sensors") {
                privilegedTemperatureStatusMessage = "Privileged mode unavailable: this macOS powermetrics output has no Celsius sensors. PulseBar is using standard thermal state."
            } else if error.localizedCaseInsensitiveContains("did not become reachable") {
                privilegedTemperatureStatusMessage = "Privileged mode blocked: helper launch did not complete. Retry privileged sampling after confirming admin prompt approval."
            } else if error.localizedCaseInsensitiveContains("superuser")
                || error.localizedCaseInsensitiveContains("authorization")
                || error.localizedCaseInsensitiveContains("permission") {
                privilegedTemperatureStatusMessage = "Privileged mode blocked: admin authorization is required for privileged temperature sampling."
            } else {
                if let retryDate = status.nextRetryAt {
                    privilegedTemperatureStatusMessage = "Privileged mode degraded: \(error). Next retry \(retryDate.formatted(date: .omitted, time: .standard))."
                } else {
                    privilegedTemperatureStatusMessage = "Privileged mode degraded: \(error)."
                }
            }

            privilegedTemperatureHealthy = false
        } else {
            if status.lastSuccessAt != nil {
                privilegedTemperatureStatusMessage = "Privileged mode active via \(status.sourceDescription)."
                privilegedTemperatureHealthy = true
            } else {
                privilegedTemperatureStatusMessage = "Privileged mode is starting. You may be prompted for administrator access."
                privilegedTemperatureHealthy = false
            }
        }

        if let lastSuccess = status.lastSuccessAt {
            privilegedTemperatureLastSuccessMessage = "Last successful privileged sample: \(lastSuccess.formatted(date: .omitted, time: .standard))."
        } else {
            privilegedTemperatureLastSuccessMessage = nil
        }

        let mappedChannels = (status.latestReading?.channels ?? [])
            .map { SensorDisplayNameMapper.present($0) }
            .sorted { lhs, rhs in
                if lhs.category != rhs.category {
                    return lhs.category.rawValue < rhs.category.rawValue
                }
                if lhs.channelType != rhs.channelType {
                    return lhs.channelType.rawValue < rhs.channelType.rawValue
                }
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

        // Persist channel samples before publishing so the chart query does not race
        // ahead of database writes and get stuck in "Collecting sensor history".
        await temperatureHistoryStore.append(channels: mappedChannels)

        latestSensorChannels = mappedChannels
        latestTemperatureSensors = mappedChannels
            .filter { $0.channelType == .temperatureCelsius }
            .map { TemperatureSensorReading(name: $0.displayName, celsius: $0.value) }
        privilegedFanTelemetryHealthy = status.fanTelemetryHealthy
        privilegedChannelsAvailable = status.channelsAvailable
        privilegedActiveSourceChain = status.activeSourceChain
        privilegedSourceDiagnostics = status.sourceDiagnostics

        let currentChannelIDs = Set(mappedChannels.map(\.id))
        let updatedHidden = hiddenTemperatureSensorIDs.filter { currentChannelIDs.contains($0) }
        if updatedHidden != hiddenTemperatureSensorIDs {
            hiddenTemperatureSensorIDs = updatedHidden
        }

        let visibleChannels = mappedChannels.filter { !hiddenTemperatureSensorIDs.contains($0.id) }
        if selectedTemperatureSensorID.isEmpty || !visibleChannels.contains(where: { $0.id == selectedTemperatureSensorID }) {
            selectedTemperatureSensorID = visibleChannels.first?.id ?? ""
        }

        let fanChannelCount = mappedChannels.filter { $0.channelType == .fanRPM }.count
        let reportedFanCount = status.latestReading?.fanCount ?? 0
        if reportedFanCount > 0 && fanChannelCount == 0 {
            fanParityGateBlocked = true
            fanParityGateMessage = "Fan hardware detected but no RPM telemetry is available from current privileged probes."
        } else if reportedFanCount <= 0 {
            fanParityGateBlocked = false
            fanParityGateMessage = "No fan hardware reported by current sources."
        } else {
            fanParityGateBlocked = false
            fanParityGateMessage = nil
        }

    }

    private func handlePowerSourceChange(_ source: PowerSourceState) async {
        currentPowerSourceDescription = source.label

        guard autoSwitchProfilesEnabled else { return }

        let targetProfile: ProfileID?
        switch source {
        case .ac:
            targetProfile = autoSwitchACProfile
        case .battery:
            targetProfile = autoSwitchBatteryProfile
        case .unknown:
            targetProfile = nil
        }

        guard let targetProfile else { return }
        guard selectedProfileID != targetProfile else { return }
        selectedProfileID = targetProfile
    }

    private func updateLaunchAtLogin() async {
        guard !bootstrapping else { return }
        guard isAppBundleRuntime else {
            launchAtLoginStatusMessage = "Launch at login requires app-bundle runtime."
            return
        }

        if #available(macOS 13.0, *) {
            do {
                if launchAtLoginEnabled {
                    try SMAppService.mainApp.register()
                    launchAtLoginStatusMessage = "Launch at login enabled"
                } else {
                    try await SMAppService.mainApp.unregister()
                    launchAtLoginStatusMessage = "Launch at login disabled"
                }
            } catch {
                launchAtLoginStatusMessage = "Launch-at-login update failed: \(error.localizedDescription)"
            }
        } else {
            launchAtLoginStatusMessage = "Launch at login requires macOS 13+"
        }
    }

    private func persist<T>(_ value: T, key: String) {
        guard !bootstrapping else { return }
        defaults.set(value, forKey: key)
    }

    private func hydrateLatestSamplesFromPersistentHistory() async {
        let persistedLatest = await metricHistoryStore.latestByMetric()
        guard !persistedLatest.isEmpty else { return }

        await store.append(Array(persistedLatest.values))
        latestSamples.merge(persistedLatest) { _, persisted in persisted }
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
        let throughputUnit = ThroughputDisplayUnit(rawValue: defaults.string(forKey: DefaultsKey.throughputUnit) ?? "") ?? .bytesPerSecond
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
        let diskFreeAlertThresholdBytes = defaults.object(forKey: DefaultsKey.diskFreeAlertThresholdBytes) as? Double ?? (20 * 1_073_741_824)
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

private enum NotificationDispatcher {
    @MainActor
    static func requestAuthorizationIfNeeded(isAppBundleRuntime: Bool) async {
        guard isAppBundleRuntime else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func send(title: String, body: String, isAppBundleRuntime: Bool) async {
        guard isAppBundleRuntime else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().add(request) { _ in
                continuation.resume()
            }
        }
    }
}
