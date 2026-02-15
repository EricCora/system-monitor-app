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
        static let throughputUnit = "settings.throughputUnit"
        static let selectedWindow = "settings.selectedWindow"
        static let launchAtLogin = "settings.launchAtLogin"
        static let cpuAlertEnabled = "settings.cpuAlertEnabled"
        static let cpuAlertThreshold = "settings.cpuAlertThreshold"
        static let cpuAlertDuration = "settings.cpuAlertDuration"
    }

    private let defaults: UserDefaults
    private let store: TimeSeriesStore
    private let alertEngine: AlertEngine
    private let samplingEngine: SamplingEngine
    private let isAppBundleRuntime: Bool

    private var bootstrapping = true

    @Published var latestSamples: [MetricID: MetricSample] = [:]
    @Published var launchAtLoginStatusMessage: String?

    @Published var sampleInterval: Double {
        didSet {
            let clamped = sampleInterval.clamped(to: 1...10)
            if clamped != sampleInterval {
                sampleInterval = clamped
                return
            }
            persist(sampleInterval, key: DefaultsKey.sampleInterval)
            Task { await samplingEngine.updateInterval(seconds: sampleInterval) }
        }
    }

    @Published var showCPUInMenu: Bool {
        didSet { persist(showCPUInMenu, key: DefaultsKey.showCPUInMenu) }
    }

    @Published var showMemoryInMenu: Bool {
        didSet { persist(showMemoryInMenu, key: DefaultsKey.showMemoryInMenu) }
    }

    @Published var showNetworkInMenu: Bool {
        didSet { persist(showNetworkInMenu, key: DefaultsKey.showNetworkInMenu) }
    }

    @Published var showDiskInMenu: Bool {
        didSet { persist(showDiskInMenu, key: DefaultsKey.showDiskInMenu) }
    }

    @Published var throughputUnit: ThroughputDisplayUnit {
        didSet { persist(throughputUnit.rawValue, key: DefaultsKey.throughputUnit) }
    }

    @Published var selectedWindow: TimeWindow {
        didSet { persist(selectedWindow.rawValue, key: DefaultsKey.selectedWindow) }
    }

    @Published var launchAtLoginEnabled: Bool {
        didSet {
            persist(launchAtLoginEnabled, key: DefaultsKey.launchAtLogin)
            Task { await updateLaunchAtLogin() }
        }
    }

    @Published var cpuAlertEnabled: Bool {
        didSet {
            persist(cpuAlertEnabled, key: DefaultsKey.cpuAlertEnabled)
            Task { await refreshAlertRule() }
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
            Task { await refreshAlertRule() }
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
            Task { await refreshAlertRule() }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isAppBundleRuntime = Bundle.main.bundleURL.pathExtension == "app"

        let sampleInterval = defaults.object(forKey: DefaultsKey.sampleInterval) as? Double ?? 2.0
        let showCPUInMenu = defaults.object(forKey: DefaultsKey.showCPUInMenu) as? Bool ?? true
        let showMemoryInMenu = defaults.object(forKey: DefaultsKey.showMemoryInMenu) as? Bool ?? true
        let showNetworkInMenu = defaults.object(forKey: DefaultsKey.showNetworkInMenu) as? Bool ?? true
        let showDiskInMenu = defaults.object(forKey: DefaultsKey.showDiskInMenu) as? Bool ?? false
        let throughputUnit = ThroughputDisplayUnit(rawValue: defaults.string(forKey: DefaultsKey.throughputUnit) ?? "") ?? .bytesPerSecond
        let selectedWindow = TimeWindow(rawValue: defaults.string(forKey: DefaultsKey.selectedWindow) ?? "") ?? .oneHour
        let launchAtLogin = defaults.object(forKey: DefaultsKey.launchAtLogin) as? Bool ?? false
        let cpuAlertEnabled = defaults.object(forKey: DefaultsKey.cpuAlertEnabled) as? Bool ?? false
        let cpuAlertThreshold = defaults.object(forKey: DefaultsKey.cpuAlertThreshold) as? Double ?? 85
        let cpuAlertDuration = defaults.object(forKey: DefaultsKey.cpuAlertDuration) as? Int ?? 30

        self.sampleInterval = sampleInterval
        self.showCPUInMenu = showCPUInMenu
        self.showMemoryInMenu = showMemoryInMenu
        self.showNetworkInMenu = showNetworkInMenu
        self.showDiskInMenu = showDiskInMenu
        self.throughputUnit = throughputUnit
        self.selectedWindow = selectedWindow
        self.launchAtLoginEnabled = launchAtLogin
        self.cpuAlertEnabled = cpuAlertEnabled
        self.cpuAlertThreshold = cpuAlertThreshold
        self.cpuAlertDuration = cpuAlertDuration

        self.store = TimeSeriesStore(defaultCapacity: 7200)

        self.alertEngine = AlertEngine { title, body in
            await NotificationDispatcher.send(title: title, body: body)
        }

        let providers: [any MetricProvider] = [
            CPUProvider(),
            MemoryProvider(),
            NetworkProvider(),
            DiskProvider()
        ]

        self.samplingEngine = SamplingEngine(
            providers: providers,
            store: store,
            intervalSeconds: sampleInterval
        )

        bootstrapping = false

        Task {
            await samplingEngine.setOnBatch { [weak self] batch in
                await self?.handle(batch: batch)
            }
            await NotificationDispatcher.requestAuthorizationIfNeeded(isAppBundleRuntime: isAppBundleRuntime)
            await refreshAlertRule()
            await updateLaunchAtLogin()
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

    private func handle(batch: [MetricSample]) async {
        await alertEngine.process(samples: batch)

        await MainActor.run {
            for sample in batch {
                latestSamples[sample.metricID] = sample
            }
        }
    }

    private func refreshAlertRule() async {
        let rule = AlertRule(
            metricID: .cpuTotalPercent,
            threshold: cpuAlertThreshold,
            durationSeconds: cpuAlertDuration,
            isEnabled: cpuAlertEnabled
        )
        await alertEngine.updateRule(rule)
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
