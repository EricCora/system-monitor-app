import Combine
import Foundation
import PulseBarCore
import ServiceManagement

struct NetworkInterfaceRate: Identifiable {
    let interface: String
    let inboundBytesPerSecond: Double
    let outboundBytesPerSecond: Double

    var id: String { interface }
    var totalBytesPerSecond: Double { inboundBytesPerSecond + outboundBytesPerSecond }
}

@MainActor
final class AppCoordinator: ObservableObject {
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
    private let diskProvider: DiskProvider
    private let alertDeliveryCenter: AlertDeliveryCenter
    private let powerSourceMonitor = PowerSourceMonitor()
    private let settingsController: SettingsController
    private let telemetryStore: TelemetryStore
    private let temperaturePaneModel: TemperaturePaneModel
    let performanceDiagnosticsStore: PerformanceDiagnosticsStore
    let dashboardStatusStore: DashboardStatusStore
    let cpuUsageSurfaceStore: CPUUsageSurfaceStore
    let cpuLoadSurfaceStore: CPULoadSurfaceStore
    let cpuProcessesSurfaceStore: CPUProcessesSurfaceStore
    let cpuGPUSurfaceStore: CPUGPUSurfaceStore
    let cpuFPSSurfaceStore: CPUFPSSurfaceStore
    let memoryFeatureStore: MemoryFeatureStore
    let batteryFeatureStore: BatteryFeatureStore
    let networkFeatureStore: NetworkFeatureStore
    let diskFeatureStore: DiskFeatureStore
    let temperatureFeatureStore: TemperatureFeatureStore

    private var cancellables = Set<AnyCancellable>()
    private var activeDashboardTab: DashboardTab?
    private var cpuProcessPollingTask: Task<Void, Never>?
    private var memoryProcessPollingTask: Task<Void, Never>?
    private var fpsStatusPollingTask: Task<Void, Never>?
    private var privilegedTemperatureRefreshTask: Task<Void, Never>?

    @Published var launchAtLoginStatusMessage: String?

    init(defaults: UserDefaults = .standard) {
        isAppBundleRuntime = Bundle.main.bundleURL.pathExtension == "app"
        let alertDeliveryCenter = AlertDeliveryCenter(isAppBundleRuntime: Bundle.main.bundleURL.pathExtension == "app")
        self.alertDeliveryCenter = alertDeliveryCenter

        let settingsController = SettingsController(defaults: defaults)
        self.settingsController = settingsController
        telemetryStore = TelemetryStore()
        temperaturePaneModel = TemperaturePaneModel(defaults: defaults)
        performanceDiagnosticsStore = PerformanceDiagnosticsStore()
        dashboardStatusStore = DashboardStatusStore()
        cpuUsageSurfaceStore = CPUUsageSurfaceStore()
        cpuLoadSurfaceStore = CPULoadSurfaceStore()
        cpuProcessesSurfaceStore = CPUProcessesSurfaceStore()
        cpuGPUSurfaceStore = CPUGPUSurfaceStore()
        cpuFPSSurfaceStore = CPUFPSSurfaceStore()
        memoryFeatureStore = MemoryFeatureStore()
        batteryFeatureStore = BatteryFeatureStore()
        networkFeatureStore = NetworkFeatureStore()
        diskFeatureStore = DiskFeatureStore()
        temperatureFeatureStore = TemperatureFeatureStore()

        store = TimeSeriesStore(defaultCapacity: 7200)
        temperatureHistoryStore = TemperatureHistoryStore()
        memoryHistoryStore = MemoryHistoryStore()
        metricHistoryStore = MetricHistoryStore()
        processMemoryProvider = ProcessMemoryProvider(
            maxEntries: 12,
            minCollectionInterval: 5
        )
        processCPUProvider = ProcessCPUProvider(
            maxEntries: 12,
            minCollectionInterval: 3
        )
        let gpuStatsProvider = GPUStatsProvider()
        self.gpuStatsProvider = gpuStatsProvider

        alertEngine = AlertEngine { title, body in
            _ = await alertDeliveryCenter.deliver(title: title, body: body)
        }

        let privilegedSource = PrivilegedHelperTemperatureDataSource()
        let powermetricsProvider = PowermetricsProvider(
            dataSource: privilegedSource,
            minCollectionInterval: settingsController.globalSamplingInterval
        )
        temperatureCoordinator = TemperatureCoordinator(provider: powermetricsProvider)
        let fpsProvider = FPSProvider(liveCaptureEnabled: settingsController.liveCompositorFPSEnabled)
        self.fpsProvider = fpsProvider

        let diskProvider = DiskProvider()
        self.diskProvider = diskProvider

        let providers: [any MetricProvider] = [
            CPUProvider(),
            ThermalStateProvider(),
            BatteryProvider(),
            MemoryProvider(),
            NetworkProvider(),
            diskProvider,
            gpuStatsProvider,
            fpsProvider,
            powermetricsProvider
        ]

        samplingEngine = SamplingEngine(
            providers: providers,
            store: store,
            intervalSeconds: settingsController.globalSamplingInterval.clamped(to: 1...10)
        )

        bindServiceChanges()
        installSettingCallbacks()

        Task {
            await gpuStatsProvider.setOnSnapshotRead { [weak self] in
                Task { @MainActor [weak self] in
                    self?.performanceDiagnosticsStore.recordGPUSnapshotRead()
                }
            }
            await diskProvider.setOnFallbackInvocation { [weak self] in
                Task { @MainActor [weak self] in
                    self?.performanceDiagnosticsStore.recordDiskFallback()
                }
            }

            await samplingEngine.setOnBatch { [weak self] batch in
                await self?.handle(batch: batch)
            }

            telemetryStore.setHistoryStartupStatus(
                metric: await metricHistoryStartupMessage(),
                memory: await memoryHistoryStartupMessage(),
                temperature: await temperatureHistoryStartupMessage()
            )

            await hydrateLatestSamplesFromPersistentHistory()
            telemetryStore.recentAlerts = alertDeliveryCenter.recentAlerts
            await alertDeliveryCenter.requestAuthorizationIfNeeded()
            await temperatureCoordinator.setPrivilegedEnabled(settingsController.privilegedTemperatureEnabled)
            await refreshAlertRules()
            await updateLaunchAtLogin(enabled: settingsController.launchAtLoginEnabled)
            telemetryStore.latestGPUSummary = await gpuStatsProvider.latestSnapshot()
            syncFeatureStoresFromLatestSamples()
            await powerSourceMonitor.start { [weak self] source in
                await self?.handlePowerSourceChange(source)
            }
            await samplingEngine.start()
            schedulePrivilegedTemperatureRefresh()
        }
    }

    var latestSamples: [MetricID: MetricSample] { telemetryStore.latestSamples }
    var latestSensorChannels: [SensorReading] { telemetryStore.latestSensorChannels }
    var latestTemperatureSensors: [TemperatureSensorReading] { telemetryStore.latestTemperatureSensors }
    var privilegedTemperatureStatusMessage: String? { telemetryStore.privilegedTemperatureStatusMessage }
    var privilegedTemperatureLastSuccessMessage: String? { telemetryStore.privilegedTemperatureLastSuccessMessage }
    var privilegedTemperatureHealthy: Bool { telemetryStore.privilegedTemperatureHealthy }
    var privilegedFanTelemetryHealthy: Bool { telemetryStore.privilegedFanTelemetryHealthy }
    var privilegedChannelsAvailable: [SensorChannelType] { telemetryStore.privilegedChannelsAvailable }
    var privilegedActiveSourceChain: [String] { telemetryStore.privilegedActiveSourceChain }
    var privilegedSourceDiagnostics: [SensorSourceDiagnostic] { telemetryStore.privilegedSourceDiagnostics }
    var fanParityGateBlocked: Bool { telemetryStore.fanParityGateBlocked }
    var fanParityGateMessage: String? { telemetryStore.fanParityGateMessage }
    var temperatureHistoryStoreStatusMessage: String? { telemetryStore.temperatureHistoryStoreStatusMessage }
    var memoryHistoryStoreStatusMessage: String? { telemetryStore.memoryHistoryStoreStatusMessage }
    var historyStoreStatusMessage: String? { telemetryStore.historyStoreStatusMessage }
    var memoryProcessesStatusMessage: String? { telemetryStore.memoryProcessesStatusMessage }
    var cpuProcessesStatusMessage: String? { telemetryStore.cpuProcessesStatusMessage }
    var currentPowerSourceDescription: String { telemetryStore.currentPowerSourceDescription }
    var topMemoryProcesses: [MemoryProcessEntry] { telemetryStore.topMemoryProcesses }
    var topCPUProcesses: [CPUProcessEntry] { telemetryStore.topCPUProcesses }
    var recentAlerts: [DeliveredAlert] { telemetryStore.recentAlerts }
    var latestGPUSummary: GPUSummarySnapshot? { telemetryStore.latestGPUSummary }
    var fpsStatusMessage: String? { telemetryStore.fpsStatusMessage }
    var recentProviderFailures: [ProviderFailure] { telemetryStore.recentProviderFailures }
    var sampleRevision: UInt64 { telemetryStore.sampleRevision }
    var metricHistoryRevision: UInt64 { telemetryStore.metricHistoryRevision }
    var memoryHistoryRevision: UInt64 { telemetryStore.memoryHistoryRevision }
    var temperatureHistoryRevision: UInt64 { telemetryStore.temperatureHistoryRevision }

    var liveCompositorFPSEnabled: Bool {
        get { settingsController.liveCompositorFPSEnabled }
        set { settingsController.liveCompositorFPSEnabled = newValue }
    }

    var selectedTemperatureSensorID: String {
        get { temperaturePaneModel.selectedTemperatureSensorID }
        set { temperaturePaneModel.selectedTemperatureSensorID = newValue }
    }

    var selectedTemperatureHistoryWindow: ChartWindow {
        get { settingsController.selectedTemperatureHistoryWindow }
        set { settingsController.selectedTemperatureHistoryWindow = newValue }
    }

    var selectedMemoryHistoryWindow: ChartWindow {
        get { settingsController.selectedMemoryHistoryWindow }
        set { settingsController.selectedMemoryHistoryWindow = newValue }
    }

    var selectedCPUHistoryWindow: ChartWindow {
        get { settingsController.selectedCPUHistoryWindow }
        set { settingsController.selectedCPUHistoryWindow = newValue }
    }

    var compactCPUChartWindow: ChartWindow {
        get { settingsController.compactCPUChartWindow }
        set { settingsController.compactCPUChartWindow = newValue }
    }

    var batteryChartWindow: ChartWindow {
        get { settingsController.batteryChartWindow }
        set { settingsController.batteryChartWindow = newValue }
    }

    var networkChartWindow: ChartWindow {
        get { settingsController.networkChartWindow }
        set { settingsController.networkChartWindow = newValue }
    }

    var diskChartWindow: ChartWindow {
        get { settingsController.diskChartWindow }
        set { settingsController.diskChartWindow = newValue }
    }

    var visibleChartWindows: [ChartWindow] {
        get { settingsController.effectiveVisibleChartWindows }
        set { settingsController.visibleChartWindows = newValue }
    }

    var selectedMemoryPaneChart: MemoryPaneChart {
        get { settingsController.selectedMemoryPaneChart }
        set { settingsController.selectedMemoryPaneChart = newValue }
    }

    var selectedCPUPaneChart: CPUPaneChart {
        get { settingsController.selectedCPUPaneChart }
        set { settingsController.selectedCPUPaneChart = newValue }
    }

    var hiddenTemperatureSensorIDs: [String] {
        get { temperaturePaneModel.hiddenTemperatureSensorIDs }
        set { temperaturePaneModel.hiddenTemperatureSensorIDs = newValue }
    }

    var globalSamplingInterval: Double {
        get { settingsController.globalSamplingInterval }
        set { settingsController.globalSamplingInterval = newValue }
    }

    var showCPUInMenu: Bool {
        get { settingsController.showCPUInMenu }
        set { settingsController.showCPUInMenu = newValue }
    }

    var showMemoryInMenu: Bool {
        get { settingsController.showMemoryInMenu }
        set { settingsController.showMemoryInMenu = newValue }
    }

    var showBatteryInMenu: Bool {
        get { settingsController.showBatteryInMenu }
        set { settingsController.showBatteryInMenu = newValue }
    }

    var showNetworkInMenu: Bool {
        get { settingsController.showNetworkInMenu }
        set { settingsController.showNetworkInMenu = newValue }
    }

    var showDiskInMenu: Bool {
        get { settingsController.showDiskInMenu }
        set { settingsController.showDiskInMenu = newValue }
    }

    var showTemperatureInMenu: Bool {
        get { settingsController.showTemperatureInMenu }
        set { settingsController.showTemperatureInMenu = newValue }
    }

    var throughputUnit: ThroughputDisplayUnit {
        get { settingsController.throughputUnit }
        set { settingsController.throughputUnit = newValue }
    }

    var chartAreaOpacity: Double {
        get { settingsController.chartAreaOpacity }
        set { settingsController.chartAreaOpacity = newValue }
    }

    var launchAtLoginEnabled: Bool {
        get { settingsController.launchAtLoginEnabled }
        set { settingsController.launchAtLoginEnabled = newValue }
    }

    var privilegedTemperatureEnabled: Bool {
        get { settingsController.privilegedTemperatureEnabled }
        set { settingsController.privilegedTemperatureEnabled = newValue }
    }

    var selectedProfileID: ProfileID {
        get { settingsController.selectedProfileID }
        set { settingsController.selectedProfileID = newValue }
    }

    var autoSwitchProfilesEnabled: Bool {
        get { settingsController.autoSwitchProfilesEnabled }
        set { settingsController.autoSwitchProfilesEnabled = newValue }
    }

    var autoSwitchACProfile: ProfileID {
        get { settingsController.autoSwitchACProfile }
        set { settingsController.autoSwitchACProfile = newValue }
    }

    var autoSwitchBatteryProfile: ProfileID {
        get { settingsController.autoSwitchBatteryProfile }
        set { settingsController.autoSwitchBatteryProfile = newValue }
    }

    var cpuAlertEnabled: Bool {
        get { settingsController.cpuAlertEnabled }
        set { settingsController.cpuAlertEnabled = newValue }
    }

    var cpuAlertThreshold: Double {
        get { settingsController.cpuAlertThreshold }
        set { settingsController.cpuAlertThreshold = newValue }
    }

    var cpuAlertDuration: Int {
        get { settingsController.cpuAlertDuration }
        set { settingsController.cpuAlertDuration = newValue }
    }

    var temperatureAlertEnabled: Bool {
        get { settingsController.temperatureAlertEnabled }
        set { settingsController.temperatureAlertEnabled = newValue }
    }

    var temperatureAlertThreshold: Double {
        get { settingsController.temperatureAlertThreshold }
        set { settingsController.temperatureAlertThreshold = newValue }
    }

    var temperatureAlertDuration: Int {
        get { settingsController.temperatureAlertDuration }
        set { settingsController.temperatureAlertDuration = newValue }
    }

    var memoryPressureAlertEnabled: Bool {
        get { settingsController.memoryPressureAlertEnabled }
        set { settingsController.memoryPressureAlertEnabled = newValue }
    }

    var memoryPressureAlertThreshold: Double {
        get { settingsController.memoryPressureAlertThreshold }
        set { settingsController.memoryPressureAlertThreshold = newValue }
    }

    var memoryPressureAlertDuration: Int {
        get { settingsController.memoryPressureAlertDuration }
        set { settingsController.memoryPressureAlertDuration = newValue }
    }

    var diskFreeAlertEnabled: Bool {
        get { settingsController.diskFreeAlertEnabled }
        set { settingsController.diskFreeAlertEnabled = newValue }
    }

    var diskFreeAlertThresholdBytes: Double {
        get { settingsController.diskFreeAlertThresholdBytes }
        set { settingsController.diskFreeAlertThresholdBytes = newValue }
    }

    var diskFreeAlertDuration: Int {
        get { settingsController.diskFreeAlertDuration }
        set { settingsController.diskFreeAlertDuration = newValue }
    }

    var cpuMenuLayout: MenuSectionLayout<CPUMenuSectionID> {
        get { settingsController.cpuMenuLayout }
        set { settingsController.cpuMenuLayout = newValue }
    }

    var memoryMenuLayout: MenuSectionLayout<MemoryMenuSectionID> {
        get { settingsController.memoryMenuLayout }
        set { settingsController.memoryMenuLayout = newValue }
    }

    var cpuProcessCount: Int {
        get { settingsController.cpuProcessCount }
        set { settingsController.cpuProcessCount = newValue }
    }

    var memoryProcessCount: Int {
        get { settingsController.memoryProcessCount }
        set { settingsController.memoryProcessCount = newValue }
    }

    func series(for metricID: MetricID, window: ChartWindow, maxPoints: Int = 300) async -> [MetricSample] {
        if telemetryStore.historyStoreStatusMessage == nil {
            return await metricHistoryStore.samples(for: metricID, window: window, maxPoints: maxPoints)
        }
        let raw = await store.series(for: metricID, window: window)
        return Downsampler.downsample(raw, maxPoints: maxPoints)
    }

    func metricHistorySeries(
        for metricID: MetricID,
        window: ChartWindow,
        maxPoints: Int = 900
    ) async -> [MetricHistoryPoint] {
        await series(for: metricID, window: window, maxPoints: maxPoints).map {
            MetricHistoryPoint(
                timestamp: $0.timestamp,
                value: $0.value,
                unit: $0.unit
            )
        }
    }

    func temperatureHistorySeries(
        sensorID: String,
        channelType: SensorChannelType,
        window: ChartWindow,
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
        window: ChartWindow,
        maxPoints: Int = 900
    ) async -> [MemoryHistoryPoint] {
        await memoryHistoryStore.series(window: window, maxPoints: maxPoints)
    }

    func cpuHistorySnapshot(
        window: ChartWindow,
        maxPoints: Int = 900
    ) async -> CPUHistorySnapshot {
        async let user = metricHistorySeries(for: .cpuUserPercent, window: window, maxPoints: maxPoints)
        async let system = metricHistorySeries(for: .cpuSystemPercent, window: window, maxPoints: maxPoints)
        async let idle = metricHistorySeries(for: .cpuIdlePercent, window: window, maxPoints: maxPoints)
        async let load1 = metricHistorySeries(for: .cpuLoadAverage1, window: window, maxPoints: maxPoints)
        async let load5 = metricHistorySeries(for: .cpuLoadAverage5, window: window, maxPoints: maxPoints)
        async let load15 = metricHistorySeries(for: .cpuLoadAverage15, window: window, maxPoints: maxPoints)
        async let gpuProcessor = metricHistorySeries(for: .gpuProcessorPercent, window: window, maxPoints: maxPoints)
        async let gpuMemory = metricHistorySeries(for: .gpuMemoryPercent, window: window, maxPoints: maxPoints)
        async let framesPerSecond = metricHistorySeries(for: .framesPerSecond, window: window, maxPoints: maxPoints)

        return await CPUHistorySnapshot(
            user: user,
            system: system,
            idle: idle,
            load1: load1,
            load5: load5,
            load15: load15,
            gpuProcessor: gpuProcessor,
            gpuMemory: gpuMemory,
            framesPerSecond: framesPerSecond
        )
    }

    func memoryHistorySnapshot(
        window: ChartWindow,
        maxPoints: Int = 900
    ) async -> MemoryHistorySnapshot {
        async let composition = memoryHistorySeries(window: window, maxPoints: maxPoints)
        async let pressure = metricHistorySeries(for: .memoryPressureLevel, window: window, maxPoints: maxPoints)
        async let swap = metricHistorySeries(for: .memorySwapUsedBytes, window: window, maxPoints: maxPoints)
        async let pageIns = metricHistorySeries(for: .memoryPageInsBytesPerSec, window: window, maxPoints: maxPoints)
        async let pageOuts = metricHistorySeries(for: .memoryPageOutsBytesPerSec, window: window, maxPoints: maxPoints)

        return await MemoryHistorySnapshot(
            composition: composition,
            pressure: pressure,
            swap: swap,
            pageIns: pageIns,
            pageOuts: pageOuts
        )
    }

    func visibleSensorChannels() -> [SensorReading] {
        temperaturePaneModel.visibleSensorChannels(from: telemetryStore.latestSensorChannels)
    }

    func selectedSensorReading(includeHidden: Bool = false) -> SensorReading? {
        temperaturePaneModel.selectedSensorReading(
            in: telemetryStore.latestSensorChannels,
            includeHidden: includeHidden
        )
    }

    func hideTemperatureSensor(sensorID: String) {
        temperaturePaneModel.hideSensor(sensorID, allSensors: telemetryStore.latestSensorChannels)
        syncTemperatureFeatureStore()
    }

    func resetHiddenTemperatureSensors() {
        temperaturePaneModel.resetHiddenSensors(allSensors: telemetryStore.latestSensorChannels)
        syncTemperatureFeatureStore()
    }

    func isTemperatureSensorHidden(sensorID: String) -> Bool {
        temperaturePaneModel.isHidden(sensorID: sensorID)
    }

    func latestValue(for metricID: MetricID) -> MetricSample? {
        telemetryStore.latestValue(for: metricID)
    }

    func hasBatteryTelemetry() -> Bool {
        telemetryStore.hasBatteryTelemetry()
    }

    func latestCPUCores() -> [MetricSample] {
        telemetryStore.latestCPUCores()
    }

    func latestNetworkInterfaces() -> [NetworkInterfaceRate] {
        telemetryStore.latestNetworkInterfaces()
    }

    func latestThermalState() -> ThermalStateLevel {
        telemetryStore.latestThermalState()
    }

    func cpuSummarySnapshot() -> CPUSummarySnapshot {
        telemetryStore.cpuSummarySnapshot()
    }

    func setActiveDashboardTab(_ tab: DashboardTab?) {
        activeDashboardTab = tab
        reevaluatePresentationSchedulers()

        guard let tab else { return }
        Task {
            switch tab {
            case .cpu:
                await refreshCPUCompactCharts(forceReload: false)
            case .battery:
                await refreshBatteryCharts(forceReload: false)
            case .network:
                await refreshNetworkCharts(forceReload: false)
            case .disk:
                await refreshDiskCharts(forceReload: false)
            case .temperature:
                syncTemperatureFeatureStore()
            case .memory, .settings:
                break
            }
        }
    }

    func refreshCPUCompactSurface(forceReload: Bool = true) {
        Task { await refreshCPUCompactCharts(forceReload: forceReload) }
    }

    func refreshBatterySurface() {
        Task { await refreshBatteryCharts(forceReload: true) }
    }

    func refreshNetworkSurface() {
        Task { await refreshNetworkCharts(forceReload: true) }
    }

    func refreshDiskSurface() {
        Task { await refreshDiskCharts(forceReload: true) }
    }

    func retryPrivilegedTemperatureNow() {
        Task {
            await temperatureCoordinator.requestImmediateRetry()
            let samples = await temperatureCoordinator.probeNow()
            await applyImmediatePrivilegedSamples(samples)
            await refreshPrivilegedTemperatureStatus()
        }
    }

    private func bindServiceChanges() {
        settingsController.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        temperaturePaneModel.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private func installSettingCallbacks() {
        settingsController.onSamplingIntervalChanged = { [weak self] seconds in
            guard let self else { return }
            await self.samplingEngine.updateInterval(seconds: seconds)
        }

        settingsController.onLiveFPSChanged = { [weak self] enabled in
            guard let self else { return }
            await self.fpsProvider.setLiveCaptureEnabled(enabled)
            await MainActor.run {
                self.telemetryStore.fpsStatusMessage = nil
                self.cpuFPSSurfaceStore.update(
                    framesPerSecond: self.telemetryStore.latestSamples[.framesPerSecond]?.value,
                    status: nil
                )
            }
            await self.refreshFPSStatus()
        }

        settingsController.onPrivilegedTemperatureToggle = { [weak self] enabled in
            guard let self else { return }
            await self.temperatureCoordinator.setPrivilegedEnabled(enabled)
            if enabled {
                let samples = await self.temperatureCoordinator.probeNow()
                await self.applyImmediatePrivilegedSamples(samples)
            }
            await self.refreshPrivilegedTemperatureStatus()
        }

        settingsController.onAlertSettingsChanged = { [weak self] in
            await self?.refreshAlertRules()
        }

        settingsController.onLaunchAtLoginChanged = { [weak self] enabled in
            await self?.updateLaunchAtLogin(enabled: enabled)
        }
    }

    private func handle(batch: SamplingBatch) async {
        let start = ContinuousClock.now
        await alertEngine.process(samples: batch.samples)

        if !batch.samples.isEmpty {
            await metricHistoryStore.append(samples: batch.samples, now: batch.timestamp)
        }

        telemetryStore.apply(batch: batch, recentAlerts: alertDeliveryCenter.recentAlerts)

        if !batch.samples.isEmpty {
            await appendMemoryHistoryPointIfAvailable(at: batch.timestamp)
            if batch.samples.contains(where: isGPUSample) {
                telemetryStore.latestGPUSummary = await gpuStatsProvider.latestSnapshot()
            }
        }

        syncFeatureStoresFromLatestSamples()
        applyVisibleSurfaceUpdates(from: batch)

        if batch.samples.contains(where: isPrivilegedTemperatureMetric) {
            schedulePrivilegedTemperatureRefresh()
        }

        let elapsed = start.duration(to: ContinuousClock.now)
        performanceDiagnosticsStore.recordBatchHandler(milliseconds: durationMilliseconds(elapsed))
    }

    private func applyImmediatePrivilegedSamples(_ samples: [MetricSample]) async {
        guard !samples.isEmpty else { return }
        await handle(batch: SamplingBatch(timestamp: samples.first?.timestamp ?? Date(), samples: samples, failures: []))
    }

    private func appendMemoryHistoryPointIfAvailable(at timestamp: Date) async {
        guard let appBytes = telemetryStore.latestSamples[.memoryAppBytes]?.value,
              let wiredBytes = telemetryStore.latestSamples[.memoryWiredBytes]?.value,
              let activeBytes = telemetryStore.latestSamples[.memoryActiveBytes]?.value,
              let compressedBytes = telemetryStore.latestSamples[.memoryCompressedBytes]?.value,
              let cacheBytes = telemetryStore.latestSamples[.memoryCacheBytes]?.value,
              let freeBytes = telemetryStore.latestSamples[.memoryFreeBytes]?.value,
              let pressurePercent = telemetryStore.latestSamples[.memoryPressureLevel]?.value else {
            return
        }

        let reportedTotal = telemetryStore.latestSamples[.memoryUsedBytes].map { $0.value + freeBytes } ?? 0
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
        telemetryStore.recordMemoryHistoryAppend()
    }

    private func refreshMemoryProcesses(at date: Date) async {
        let entries = await processMemoryProvider.topProcesses(at: date)
        let status = await processMemoryProvider.statusMessage()
        telemetryStore.updateMemoryProcesses(entries, count: settingsController.memoryProcessCount, status: status)
        memoryFeatureStore.updateProcesses(entries: Array(entries.prefix(settingsController.memoryProcessCount)), status: telemetryStore.memoryProcessesStatusMessage)
        performanceDiagnosticsStore.recordMemoryProcessPoll(at: date)
    }

    private func refreshCPUProcesses(at date: Date) async {
        let entries = await processCPUProvider.topProcesses(at: date)
        let status = await processCPUProvider.statusMessage()
        telemetryStore.updateCPUProcesses(entries, count: settingsController.cpuProcessCount, status: status)
        cpuProcessesSurfaceStore.update(entries: Array(entries.prefix(settingsController.cpuProcessCount)), status: telemetryStore.cpuProcessesStatusMessage)
        performanceDiagnosticsStore.recordCPUProcessPoll(at: date)
    }

    private func refreshFPSStatus() async {
        let status = await fpsProvider.currentStatusMessage()
        telemetryStore.fpsStatusMessage = status
        cpuFPSSurfaceStore.update(
            framesPerSecond: telemetryStore.latestSamples[.framesPerSecond]?.value,
            status: status
        )
        performanceDiagnosticsStore.recordFPSStatusRefresh()
    }

    private func refreshAlertRules() async {
        await alertEngine.updateRules(settingsController.currentAlertRules())
    }

    private func refreshPrivilegedTemperatureStatus() async {
        performanceDiagnosticsStore.recordPrivilegedStatusRefresh()
        let status = await temperatureCoordinator.currentStatus()

        if !status.isEnabled {
            telemetryStore.clearTemperatureTelemetry(
                statusMessage: "Privileged mode off (standard thermal state only)."
            )
            return
        }

        let statusMessage: String
        let isHealthy: Bool

        if let error = status.lastErrorMessage {
            if error.localizedCaseInsensitiveContains("cancelled")
                || error.localizedCaseInsensitiveContains("canceled") {
                statusMessage = "Privileged mode blocked: administrator authorization was cancelled. PulseBar is using standard thermal state."
            } else if error.localizedCaseInsensitiveContains("launch failed") {
                statusMessage = "Privileged mode blocked: helper launch failed. Retry and confirm administrator approval."
            } else if error.localizedCaseInsensitiveContains("binary not found") {
                statusMessage = "Privileged mode blocked: helper binary not found. Build PulseBarPrivilegedHelper and retry."
            } else if error.localizedCaseInsensitiveContains("not available yet") {
                statusMessage = "Privileged mode is starting. Waiting for helper readiness."
            } else if error.localizedCaseInsensitiveContains("empty response") {
                statusMessage = "Privileged mode degraded: helper started but no data was returned. Retrying automatically."
            } else if error.localizedCaseInsensitiveContains("did not expose celsius temperature sensors") {
                statusMessage = "Privileged mode unavailable: this macOS powermetrics output has no Celsius sensors. PulseBar is using standard thermal state."
            } else if error.localizedCaseInsensitiveContains("did not become reachable") {
                statusMessage = "Privileged mode blocked: helper launch did not complete. Retry privileged sampling after confirming admin prompt approval."
            } else if error.localizedCaseInsensitiveContains("superuser")
                || error.localizedCaseInsensitiveContains("authorization")
                || error.localizedCaseInsensitiveContains("permission") {
                statusMessage = "Privileged mode blocked: admin authorization is required for privileged temperature sampling."
            } else if let retryDate = status.nextRetryAt {
                statusMessage = "Privileged mode degraded: \(error). Next retry \(retryDate.formatted(date: .omitted, time: .standard))."
            } else {
                statusMessage = "Privileged mode degraded: \(error)."
            }

            isHealthy = false
        } else if status.lastSuccessAt != nil {
            statusMessage = "Privileged mode active via \(status.sourceDescription)."
            isHealthy = true
        } else {
            statusMessage = "Privileged mode is starting. You may be prompted for administrator access."
            isHealthy = false
        }

        let lastSuccessMessage = status.lastSuccessAt.map {
            "Last successful privileged sample: \($0.formatted(date: .omitted, time: .standard))."
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

        await temperatureHistoryStore.append(channels: mappedChannels)
        temperaturePaneModel.reconcileVisibleSensors(mappedChannels)

        let fanChannelCount = mappedChannels.filter { $0.channelType == .fanRPM }.count
        let reportedFanCount = status.latestReading?.fanCount ?? 0
        let fanParityGateBlocked: Bool
        let fanParityGateMessage: String?
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

        telemetryStore.updateTemperatureTelemetry(
            channels: mappedChannels,
            temperatureSensors: mappedChannels
                .filter { $0.channelType == .temperatureCelsius }
                .map { TemperatureSensorReading(name: $0.displayName, celsius: $0.value) },
            statusMessage: statusMessage,
            lastSuccessMessage: lastSuccessMessage,
            healthy: isHealthy,
            fanHealthy: status.fanTelemetryHealthy,
            channelsAvailable: status.channelsAvailable,
            activeSourceChain: status.activeSourceChain,
            sourceDiagnostics: status.sourceDiagnostics,
            fanParityGateBlocked: fanParityGateBlocked,
            fanParityGateMessage: fanParityGateMessage
        )
        syncTemperatureFeatureStore()
    }

    private func handlePowerSourceChange(_ source: PowerSourceState) async {
        telemetryStore.currentPowerSourceDescription = source.label
        syncFeatureStoresFromLatestSamples()

        // Power-source transitions are the most noticeable battery-telemetry changes,
        // so trigger an immediate sampling pass instead of waiting for the next timer tick.
        await samplingEngine.sampleNow()

        guard settingsController.autoSwitchProfilesEnabled else { return }

        let targetProfile: ProfileID?
        switch source {
        case .ac:
            targetProfile = settingsController.autoSwitchACProfile
        case .battery:
            targetProfile = settingsController.autoSwitchBatteryProfile
        case .unknown:
            targetProfile = nil
        }

        guard let targetProfile else { return }
        settingsController.applyAutoSwitchProfile(targetProfile)
    }

    private func syncFeatureStoresFromLatestSamples() {
        let cpuSummary = telemetryStore.cpuSummarySnapshot()
        dashboardStatusStore.update(
            currentPowerSourceDescription: telemetryStore.currentPowerSourceDescription,
            privilegedTemperatureStatusMessage: telemetryStore.privilegedTemperatureStatusMessage,
            privilegedTemperatureHealthy: telemetryStore.privilegedTemperatureHealthy,
            providerFailureCount: telemetryStore.recentProviderFailures.count
        )
        cpuUsageSurfaceStore.updateSummary(
            summary: cpuSummary,
            coreSamples: telemetryStore.latestCPUCores()
        )
        cpuLoadSurfaceStore.updateSummary(cpuSummary.loadAverages)
        cpuGPUSurfaceStore.update(summary: telemetryStore.latestGPUSummary)
        cpuFPSSurfaceStore.update(
            framesPerSecond: cpuSummary.framesPerSecond,
            status: telemetryStore.fpsStatusMessage
        )
        memoryFeatureStore.updateMetrics(from: telemetryStore.latestSamples)
        batteryFeatureStore.updateMetrics(from: telemetryStore.latestSamples)
        networkFeatureStore.updateMetrics(
            from: telemetryStore.latestSamples,
            interfaceRates: telemetryStore.latestNetworkInterfaces()
        )
        diskFeatureStore.updateMetrics(from: telemetryStore.latestSamples)
        syncTemperatureFeatureStore()
    }

    private func syncTemperatureFeatureStore() {
        temperatureFeatureStore.update(
            visibleSensors: temperaturePaneModel.visibleSensorChannels(from: telemetryStore.latestSensorChannels),
            privilegedTemperatureStatusMessage: telemetryStore.privilegedTemperatureStatusMessage,
            privilegedTemperatureLastSuccessMessage: telemetryStore.privilegedTemperatureLastSuccessMessage,
            privilegedTemperatureHealthy: telemetryStore.privilegedTemperatureHealthy,
            privilegedSourceDiagnostics: telemetryStore.privilegedSourceDiagnostics,
            fanParityGateBlocked: telemetryStore.fanParityGateBlocked,
            fanParityGateMessage: telemetryStore.fanParityGateMessage,
            temperatureHistoryStoreStatusMessage: telemetryStore.temperatureHistoryStoreStatusMessage
        )
    }

    private func applyVisibleSurfaceUpdates(from batch: SamplingBatch) {
        let timestamp = batch.timestamp
        cpuUsageSurfaceStore.appendSamples(batch.samples, at: timestamp)
        cpuLoadSurfaceStore.appendSamples(batch.samples, at: timestamp)
        batteryFeatureStore.appendCompactSamples(batch.samples, at: timestamp)
        networkFeatureStore.appendCompactSamples(batch.samples, at: timestamp)
        diskFeatureStore.appendCompactSamples(batch.samples, at: timestamp)
    }

    private func reevaluatePresentationSchedulers() {
        if needsCPUProcessPolling {
            startCPUProcessPollingIfNeeded()
        } else {
            cpuProcessPollingTask?.cancel()
            cpuProcessPollingTask = nil
        }

        if needsMemoryProcessPolling {
            startMemoryProcessPollingIfNeeded()
        } else {
            memoryProcessPollingTask?.cancel()
            memoryProcessPollingTask = nil
        }

        if needsFPSStatusRefresh {
            startFPSStatusPollingIfNeeded()
        } else {
            fpsStatusPollingTask?.cancel()
            fpsStatusPollingTask = nil
        }

        performanceDiagnosticsStore.updateSurfaceActivitySummary(surfaceActivitySummary)
    }

    private var needsCPUProcessPolling: Bool {
        activeDashboardTab == .cpu && settingsController.cpuMenuLayout.visibleSections.contains(.processes)
    }

    private var needsMemoryProcessPolling: Bool {
        activeDashboardTab == .memory && settingsController.memoryMenuLayout.visibleSections.contains(.processes)
    }

    private var needsFPSStatusRefresh: Bool {
        activeDashboardTab == .cpu && settingsController.cpuMenuLayout.visibleSections.contains(.framesPerSecond)
    }

    private func startCPUProcessPollingIfNeeded() {
        guard cpuProcessPollingTask == nil else { return }
        cpuProcessPollingTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshCPUProcesses(at: Date())
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                guard await MainActor.run(body: { self.needsCPUProcessPolling }) else { continue }
                await self.refreshCPUProcesses(at: Date())
            }
        }
    }

    private func startMemoryProcessPollingIfNeeded() {
        guard memoryProcessPollingTask == nil else { return }
        memoryProcessPollingTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshMemoryProcesses(at: Date())
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                guard await MainActor.run(body: { self.needsMemoryProcessPolling }) else { continue }
                await self.refreshMemoryProcesses(at: Date())
            }
        }
    }

    private func startFPSStatusPollingIfNeeded() {
        guard fpsStatusPollingTask == nil else { return }
        fpsStatusPollingTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshFPSStatus()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                guard await MainActor.run(body: { self.needsFPSStatusRefresh }) else { continue }
                await self.refreshFPSStatus()
            }
        }
    }

    private var surfaceActivitySummary: String {
        var surfaces: [String] = []
        if let activeDashboardTab {
            surfaces.append("tab:\(activeDashboardTab.title)")
        }
        if cpuProcessPollingTask != nil {
            surfaces.append("cpu-processes")
        }
        if memoryProcessPollingTask != nil {
            surfaces.append("memory-processes")
        }
        if fpsStatusPollingTask != nil {
            surfaces.append("fps")
        }
        if privilegedTemperatureRefreshTask != nil {
            surfaces.append("priv-temp")
        }
        return surfaces.isEmpty ? "No active surfaces" : surfaces.joined(separator: " • ")
    }

    private func refreshCPUCompactCharts(forceReload: Bool) async {
        let window = settingsController.compactCPUChartWindow
        let needsHydration = cpuUsageSurfaceStore.needsHydration(for: window) || cpuLoadSurfaceStore.needsHydration(for: window)
        guard forceReload || needsHydration else {
            return
        }

        async let user = series(for: .cpuUserPercent, window: window, maxPoints: 120)
        async let system = series(for: .cpuSystemPercent, window: window, maxPoints: 120)
        async let load1 = series(for: .cpuLoadAverage1, window: window, maxPoints: 120)
        async let load5 = series(for: .cpuLoadAverage5, window: window, maxPoints: 120)
        async let load15 = series(for: .cpuLoadAverage15, window: window, maxPoints: 120)

        cpuUsageSurfaceStore.setChartSamples(
            user: await user,
            system: await system,
            window: window
        )
        cpuLoadSurfaceStore.setChartSamples(load1: await load1, load5: await load5, load15: await load15, window: window)
        performanceDiagnosticsStore.recordCompactChartReload()
    }

    private func refreshBatteryCharts(forceReload: Bool) async {
        let window = settingsController.batteryChartWindow
        guard forceReload || batteryFeatureStore.chargeSamples.isEmpty else {
            return
        }

        async let charge = series(for: .batteryChargePercent, window: window, maxPoints: 120)
        async let power = series(for: .batteryPowerWatts, window: window, maxPoints: 120)
        batteryFeatureStore.setChartSamples(charge: await charge, power: await power, window: window)
        performanceDiagnosticsStore.recordCompactChartReload()
    }

    private func refreshNetworkCharts(forceReload: Bool) async {
        let window = settingsController.networkChartWindow
        guard forceReload || networkFeatureStore.inboundSamples.isEmpty else {
            return
        }

        async let inbound = series(for: .networkInBytesPerSec, window: window, maxPoints: 120)
        async let outbound = series(for: .networkOutBytesPerSec, window: window, maxPoints: 120)
        networkFeatureStore.setChartSamples(inbound: await inbound, outbound: await outbound, window: window)
        performanceDiagnosticsStore.recordCompactChartReload()
    }

    private func refreshDiskCharts(forceReload: Bool) async {
        let window = settingsController.diskChartWindow
        guard forceReload || diskFeatureStore.throughputSamples.isEmpty else {
            return
        }

        async let read = series(for: .diskReadBytesPerSec, window: window, maxPoints: 120)
        async let write = series(for: .diskWriteBytesPerSec, window: window, maxPoints: 120)
        async let throughput = series(for: .diskThroughputBytesPerSec, window: window, maxPoints: 120)
        diskFeatureStore.setChartSamples(read: await read, write: await write, throughput: await throughput, window: window)
        performanceDiagnosticsStore.recordCompactChartReload()
    }

    private func schedulePrivilegedTemperatureRefresh() {
        guard privilegedTemperatureRefreshTask == nil else { return }
        privilegedTemperatureRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshPrivilegedTemperatureStatus()
            await MainActor.run {
                self.privilegedTemperatureRefreshTask = nil
                self.performanceDiagnosticsStore.updateSurfaceActivitySummary(self.surfaceActivitySummary)
            }
        }
        performanceDiagnosticsStore.updateSurfaceActivitySummary(surfaceActivitySummary)
    }

    private func isGPUSample(_ sample: MetricSample) -> Bool {
        switch sample.metricID {
        case .gpuProcessorPercent, .gpuMemoryPercent:
            return true
        default:
            return false
        }
    }

    private func isPrivilegedTemperatureMetric(_ sample: MetricSample) -> Bool {
        sample.metricID == .temperaturePrimaryCelsius || sample.metricID == .temperatureMaxCelsius
    }

    private func updateLaunchAtLogin(enabled: Bool) async {
        guard isAppBundleRuntime else {
            launchAtLoginStatusMessage = "Launch at login requires app-bundle runtime."
            return
        }

        if #available(macOS 13.0, *) {
            do {
                if enabled {
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

    private func hydrateLatestSamplesFromPersistentHistory() async {
        let persistedLatest = await metricHistoryStore.latestByMetric()
        guard !persistedLatest.isEmpty else { return }

        await store.append(Array(persistedLatest.values))
        telemetryStore.latestSamples.merge(persistedLatest) { _, persisted in persisted }
        telemetryStore.sampleRevision &+= 1
    }

    private func metricHistoryStartupMessage() async -> String? {
        if let error = await metricHistoryStore.startupError() {
            return "Metric history database unavailable: \(error)"
        }
        return nil
    }

    private func memoryHistoryStartupMessage() async -> String? {
        if let error = await memoryHistoryStore.startupError() {
            return "Memory history database unavailable: \(error)"
        }
        return nil
    }

    private func temperatureHistoryStartupMessage() async -> String? {
        if let error = await temperatureHistoryStore.startupError() {
            return "Temperature history database unavailable: \(error)"
        }
        return nil
    }
}
