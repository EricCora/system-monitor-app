import Foundation
import Combine
import PulseBarCore
import ServiceManagement
import UserNotifications

@MainActor
final class AppCoordinator: ObservableObject {
    private enum DefaultsKey {
        static let sampleInterval = "settings.sampleInterval"
        static let showCPUInMenu = "settings.showCPUInMenu"
        static let showMemoryInMenu = "settings.showMemoryInMenu"
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
        static let selectedProfileID = "settings.selectedProfileID"
        static let autoSwitchEnabled = "settings.autoSwitchEnabled"
        static let autoSwitchACProfile = "settings.autoSwitchACProfile"
        static let autoSwitchBatteryProfile = "settings.autoSwitchBatteryProfile"
        static let privilegedTemperatureEnabled = "settings.privilegedTemperatureEnabled"
        static let appSettingsV2 = "settings.v2.data"
    }

    private let defaults: UserDefaults
    private let store: TimeSeriesStore
    private let alertEngine: AlertEngine
    private let samplingEngine: SamplingEngine
    private let isAppBundleRuntime: Bool
    private let temperatureCoordinator: TemperatureCoordinator
    private let powerSourceMonitor = PowerSourceMonitor()

    private var bootstrapping = true
    private var isApplyingProfile = false
    private var customProfileSettings: ProfileSettings

    @Published var latestSamples: [MetricID: MetricSample] = [:]
    @Published var launchAtLoginStatusMessage: String?
    @Published var privilegedTemperatureStatusMessage: String?
    @Published var privilegedTemperatureLastSuccessMessage: String?
    @Published var privilegedTemperatureHealthy: Bool = false
    @Published var currentPowerSourceDescription: String = "Unknown"

    @Published var sampleInterval: Double {
        didSet {
            let clamped = sampleInterval.clamped(to: 1...10)
            if clamped != sampleInterval {
                sampleInterval = clamped
                return
            }
            persist(sampleInterval, key: DefaultsKey.sampleInterval)
            Task { await samplingEngine.updateInterval(seconds: sampleInterval) }
            onProfileControlledSettingChanged()
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
            persistAppSettingsV2()
            Task {
                await temperatureCoordinator.setPrivilegedEnabled(privilegedTemperatureEnabled)
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
            persistAppSettingsV2()
        }
    }

    @Published var autoSwitchACProfile: ProfileID {
        didSet {
            persist(autoSwitchACProfile.rawValue, key: DefaultsKey.autoSwitchACProfile)
            persistAppSettingsV2()
        }
    }

    @Published var autoSwitchBatteryProfile: ProfileID {
        didSet {
            persist(autoSwitchBatteryProfile.rawValue, key: DefaultsKey.autoSwitchBatteryProfile)
            persistAppSettingsV2()
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isAppBundleRuntime = Bundle.main.bundleURL.pathExtension == "app"

        let legacy = AppCoordinator.loadLegacySnapshot(defaults: defaults)
        let loadedV2 = AppCoordinator.loadSettingsV2(defaults: defaults)
        let launchAtLogin = defaults.object(forKey: DefaultsKey.launchAtLogin) as? Bool ?? false

        let activeProfile: ProfileID
        let customProfile: ProfileSettings
        let autoSwitchRules: ProfileAutoSwitchRules
        let privilegedTemperatureEnabled: Bool
        let profileSettings: ProfileSettings

        if let loadedV2 {
            activeProfile = loadedV2.activeProfile
            customProfile = loadedV2.customProfile
            autoSwitchRules = loadedV2.autoSwitchRules
            privilegedTemperatureEnabled = loadedV2.privilegedTemperatureEnabled
            profileSettings = loadedV2.settings(for: loadedV2.activeProfile)
        } else {
            activeProfile = .custom
            customProfile = legacy.asProfileSettings()
            autoSwitchRules = .defaults
            privilegedTemperatureEnabled = defaults.object(forKey: DefaultsKey.privilegedTemperatureEnabled) as? Bool ?? false
            profileSettings = legacy.asProfileSettings()
        }

        self.customProfileSettings = customProfile

        self.sampleInterval = profileSettings.sampleInterval.clamped(to: 1...10)
        self.showCPUInMenu = profileSettings.showCPUInMenu
        self.showMemoryInMenu = profileSettings.showMemoryInMenu
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

        self.store = TimeSeriesStore(defaultCapacity: 7200)

        self.alertEngine = AlertEngine { title, body in
            await NotificationDispatcher.send(title: title, body: body)
        }

        let privilegedSource = PrivilegedHelperTemperatureDataSource()
        let powermetricsProvider = PowermetricsProvider(dataSource: privilegedSource)
        self.temperatureCoordinator = TemperatureCoordinator(provider: powermetricsProvider)

        let providers: [any MetricProvider] = [
            CPUProvider(),
            ThermalStateProvider(),
            MemoryProvider(),
            NetworkProvider(),
            DiskProvider(),
            powermetricsProvider
        ]

        self.samplingEngine = SamplingEngine(
            providers: providers,
            store: store,
            intervalSeconds: profileSettings.sampleInterval.clamped(to: 1...10)
        )

        bootstrapping = false
        if loadedV2 == nil {
            persistAppSettingsV2()
        }

        Task {
            await samplingEngine.setOnBatch { [weak self] batch in
                await self?.handle(batch: batch)
            }
            await NotificationDispatcher.requestAuthorizationIfNeeded(isAppBundleRuntime: isAppBundleRuntime)
            await temperatureCoordinator.setPrivilegedEnabled(privilegedTemperatureEnabled)
            await refreshAlertRules()
            await updateLaunchAtLogin()
            await refreshPrivilegedTemperatureStatus()
            await powerSourceMonitor.start { [weak self] source in
                await self?.handlePowerSourceChange(source)
            }
            await samplingEngine.start()
        }
    }

    func series(for metricID: MetricID, window: TimeWindow? = nil, maxPoints: Int = 300) async -> [MetricSample] {
        let selected = window ?? selectedWindow
        let raw = await store.series(for: metricID, window: selected)
        return Downsampler.downsample(raw, maxPoints: maxPoints)
    }

    func latestValue(for metricID: MetricID) -> MetricSample? {
        latestSamples[metricID]
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

    func latestThermalState() -> ThermalStateLevel {
        let value = latestSamples[.thermalStateLevel]?.value ?? ThermalStateLevel.nominal.metricValue
        return ThermalStateLevel.from(metricValue: value)
    }

    func retryPrivilegedTemperatureNow() {
        Task {
            await temperatureCoordinator.requestImmediateRetry()
            await refreshPrivilegedTemperatureStatus()
        }
    }

    private func handle(batch: [MetricSample]) async {
        await alertEngine.process(samples: batch)

        await MainActor.run {
            for sample in batch {
                latestSamples[sample.metricID] = sample
            }
        }

        await refreshPrivilegedTemperatureStatus()
    }

    private func refreshAlertRules() async {
        let rules = [
            AlertRule(
                metricID: .cpuTotalPercent,
                threshold: cpuAlertThreshold,
                durationSeconds: cpuAlertDuration,
                isEnabled: cpuAlertEnabled
            ),
            AlertRule(
                metricID: .temperatureMaxCelsius,
                threshold: temperatureAlertThreshold,
                durationSeconds: temperatureAlertDuration,
                isEnabled: temperatureAlertEnabled
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
        sampleInterval = settings.sampleInterval
        showCPUInMenu = settings.showCPUInMenu
        showMemoryInMenu = settings.showMemoryInMenu
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
        isApplyingProfile = false
        persistAppSettingsV2()
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

    private func onProfileControlledSettingChanged() {
        guard !bootstrapping else { return }

        if isApplyingProfile {
            persistAppSettingsV2()
            return
        }

        customProfileSettings = currentProfileSettings()
        if selectedProfileID != .custom {
            selectedProfileID = .custom
            return
        }

        persistAppSettingsV2()
    }

    private func persistAppSettingsV2() {
        guard !bootstrapping else { return }
        let settings = AppSettingsV2(
            activeProfile: selectedProfileID,
            customProfile: customProfileSettings,
            autoSwitchRules: ProfileAutoSwitchRules(
                isEnabled: autoSwitchProfilesEnabled,
                acProfile: autoSwitchACProfile,
                batteryProfile: autoSwitchBatteryProfile
            ),
            privilegedTemperatureEnabled: privilegedTemperatureEnabled
        )

        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: DefaultsKey.appSettingsV2)
    }

    private func refreshPrivilegedTemperatureStatus() async {
        let status = await temperatureCoordinator.currentStatus()

        if !status.isEnabled {
            privilegedTemperatureStatusMessage = "Privileged mode off (standard thermal state only)."
            privilegedTemperatureLastSuccessMessage = nil
            privilegedTemperatureHealthy = false
            return
        }

        if let error = status.lastErrorMessage {
            if error.localizedCaseInsensitiveContains("cancelled")
                || error.localizedCaseInsensitiveContains("canceled") {
                privilegedTemperatureStatusMessage = "Privileged mode blocked: administrator authorization was cancelled. PulseBar is using standard thermal state."
            } else if error.localizedCaseInsensitiveContains("binary not found") {
                privilegedTemperatureStatusMessage = "Privileged mode blocked: helper binary not found. Build PulseBarPrivilegedHelper and retry."
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

    private static func loadSettingsV2(defaults: UserDefaults) -> AppSettingsV2? {
        guard let data = defaults.data(forKey: DefaultsKey.appSettingsV2) else {
            return nil
        }
        return try? JSONDecoder().decode(AppSettingsV2.self, from: data)
    }

    private static func loadLegacySnapshot(defaults: UserDefaults) -> LegacySettingsSnapshot {
        let sampleInterval = defaults.object(forKey: DefaultsKey.sampleInterval) as? Double ?? 2.0
        let showCPUInMenu = defaults.object(forKey: DefaultsKey.showCPUInMenu) as? Bool ?? true
        let showMemoryInMenu = defaults.object(forKey: DefaultsKey.showMemoryInMenu) as? Bool ?? true
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

        return LegacySettingsSnapshot(
            sampleInterval: sampleInterval.clamped(to: 1...10),
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

private enum NotificationDispatcher {
    @MainActor
    static func requestAuthorizationIfNeeded(isAppBundleRuntime: Bool) async {
        guard isAppBundleRuntime else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func send(title: String, body: String) async {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }

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

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
